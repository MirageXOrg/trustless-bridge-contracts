import hashlib
import requests
import json
from ecdsa import SigningKey, SECP256k1
from ecdsa.numbertheory import inverse_mod
from ecdsa.ellipticcurve import Point
import base58
from eth_utils import keccak


def abi_encode_packed(*args) -> bytes:
    out = b""
    for arg in args:
        if isinstance(arg, bytes):
            out += arg
        elif isinstance(arg, int):
            out += arg.to_bytes(32, 'big')
        else:
            raise TypeError("Unsupported type in abi_encode_packed")
    return out

def debug_rfc6979_final_check(private_key_bytes: bytes, msg_hash_bytes: bytes):
    v = b"\x01" + b"\x00" * 31
    k = b"\x00" * 32
    k = keccak(abi_encode_packed(k + v + b'\x00' + private_key_bytes + msg_hash_bytes))
    v = keccak(abi_encode_packed(k + v))
    k = keccak(abi_encode_packed(k + v + b'\x01' + private_key_bytes + msg_hash_bytes))
    v = keccak(abi_encode_packed(k + v))
    candidate_k = int.from_bytes(v, 'big')
    return (candidate_k % (SECP256k1.order - 1)) + 1

def calculate_amounts(utxo_amount_sat, amount_to_send_sat, fee_rate_sat_per_byte=1, estimated_tx_size_bytes=250):
    fee = fee_rate_sat_per_byte * estimated_tx_size_bytes
    change = utxo_amount_sat - amount_to_send_sat - fee
    if change < 0:
        raise ValueError("Not enough funds to cover destination + fee.")
    return amount_to_send_sat, change, fee

def get_all_utxos(address: str):
    url = f"https://blockstream.info/testnet/api/address/{address}/utxo"
    utxos = requests.get(url).json()
    if not utxos:
        raise Exception("No UTXOs available")
    return utxos

def send_custom_signed_transaction(
    private_key_hex: str,
    utxos: list,
    destination_address: str,
    destination_amount_sat: int,
    change_address: str,
    change_amount_sat: int,
    rpc_url: str
):
    from bitcoin import SelectParams
    from bitcoin.wallet import CBitcoinAddress
    from bitcoin.core import COIN, lx
    from bitcoin.core.script import CScript
    from bitcoin.core import COutPoint, CTxIn, CTxOut, CTransaction
    from bitcoin.core.script import SignatureHash, SIGHASH_ALL

    SelectParams("testnet")
    
    # Create inputs from all UTXOs
    txins = []
    for utxo in utxos:
        outpoint = COutPoint(lx(utxo["txid"]), utxo["vout"])
        txins.append(CTxIn(outpoint))
    
    txout_dest = CTxOut(destination_amount_sat, CBitcoinAddress(destination_address).to_scriptPubKey())
    txout_change = CTxOut(change_amount_sat, CBitcoinAddress(change_address).to_scriptPubKey())
    
    # Create initial transaction without scriptSig
    tx = CTransaction(txins, [txout_dest, txout_change])

    private_key_bytes = bytes.fromhex(private_key_hex)
    sk = SigningKey.from_string(private_key_bytes, curve=SECP256k1)
    vk = sk.verifying_key
    pubkey = b'\x04' + vk.to_string()

    # Sign each input
    signed_txins = []
    for i, utxo in enumerate(utxos):
        sighash_script = CBitcoinAddress(change_address).to_scriptPubKey()
        sighash = SignatureHash(sighash_script, tx, i, SIGHASH_ALL)
        k = debug_rfc6979_final_check(private_key_bytes, sighash)

        G = SECP256k1.generator
        n = SECP256k1.order
        z = int.from_bytes(sighash, 'big')
        d = int.from_bytes(private_key_bytes, 'big')
        R: Point = k * G
        r = R.x() % n
        s = (inverse_mod(k, n) * (z + r * d)) % n
        if s > n // 2:
            s = n - s

        # Convert r and s to DER format
        def int_to_der_bytes(i):
            b = i.to_bytes(32, 'big')
            # Remove leading zeros
            b = b.lstrip(b'\x00')
            # If the first bit is set, prepend a zero byte
            if b[0] & 0x80:
                b = b'\x00' + b
            return b

        r_bytes = int_to_der_bytes(r)
        s_bytes = int_to_der_bytes(s)

        # Create DER signature
        der_sig = b'\x30'  # DER sequence tag
        der_sig += bytes([4 + len(r_bytes) + len(s_bytes)])  # Length of sequence
        der_sig += b'\x02'  # Integer tag
        der_sig += bytes([len(r_bytes)])  # Length of r
        der_sig += r_bytes  # r value
        der_sig += b'\x02'  # Integer tag
        der_sig += bytes([len(s_bytes)])  # Length of s
        der_sig += s_bytes  # s value
        der_sig += b'\x01'  # SIGHASH_ALL

        outpoint = COutPoint(lx(utxo["txid"]), utxo["vout"])
        signed_txins.append(CTxIn(outpoint, CScript([der_sig, pubkey])))
    
    # Create final transaction with all signed inputs
    tx = CTransaction(signed_txins, [txout_dest, txout_change])
    raw_tx_hex = tx.serialize().hex()

    response = requests.post(
        rpc_url,
        headers={'content-type': 'application/json'},
        data=json.dumps({
            "jsonrpc": "1.0",
            "id": "sendtx",
            "method": "sendrawtransaction",
            "params": [raw_tx_hex]
        })
    )
    return response.json()

# === Config ===
private_key_hex = "" # input your private key here
private_key_bytes = bytes.fromhex(private_key_hex)
sk = SigningKey.from_string(private_key_bytes, curve=SECP256k1)
vk = sk.verifying_key
public_key_bytes = b'\x04' + vk.to_string()
sha256_hash = hashlib.sha256(public_key_bytes).digest()
ripemd160 = hashlib.new("ripemd160")
ripemd160.update(sha256_hash)
pubkey_hash = ripemd160.digest()
versioned = b'\x6f' + pubkey_hash
checksum = hashlib.sha256(hashlib.sha256(versioned).digest()).digest()[:4]
address_bytes = versioned + checksum
address = base58.b58encode(address_bytes).decode()

print(address)
print(private_key_hex)

# === Get UTXOs and Calculate ===
utxos = get_all_utxos(address)
total_balance = sum(utxo["value"] for utxo in utxos)
print(f"Total balance: {total_balance} satoshis")
print("UTXOs:", utxos)

destination_amount_sat = 4000  # 0.00001 BTC
estimated_tx_size_bytes = 255 * len(utxos)  # Adjust size based on number of inputs
destination_amount_sat, change_amount_sat, fee = calculate_amounts(total_balance, destination_amount_sat, estimated_tx_size_bytes=estimated_tx_size_bytes)

# === Send transaction ===
tx_result = send_custom_signed_transaction(
    private_key_hex=private_key_hex,
    utxos=utxos,
    destination_address="tb1qv0jerhgyxpa7n48qghsuufwrmxh5xt969m9475",
    destination_amount_sat=destination_amount_sat,
    change_address=address,
    change_amount_sat=change_amount_sat,
    rpc_url="https://bitcoin-testnet-rpc.publicnode.com/"
)

print("Transaction result:", tx_result)

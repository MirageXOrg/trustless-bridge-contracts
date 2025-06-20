import binascii
from bitcoinlib.keys import Key

def private_key_to_address(private_key_hex):
    try:
        # Remove '0x' prefix if present
        if private_key_hex.startswith('0x'):
            private_key_hex = private_key_hex[2:]
        # Convert hex to bytes
        private_key_bytes = binascii.unhexlify(private_key_hex)
        # Create a key from the private key bytes
        key = Key(private_key_bytes, network='testnet', compressed=False)
        address = key.address()
        print(f"Bitcoin Testnet Address (Uncompressed): {address}")
        return address
    except Exception as e:
        print(f"Error: {str(e)}")
        return None

if __name__ == "__main__":        
    private_key = "0xe152315c0cb5b13f6074a29f06a7d85a23d20acc7c371e6d5e0eeeedf4bde352"
    private_key_to_address(private_key) 
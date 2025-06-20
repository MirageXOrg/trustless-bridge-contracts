// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Subcall} from "@oasisprotocol/sapphire-contracts/contracts/Subcall.sol";
import {SiweAuth} from "@oasisprotocol/sapphire-contracts/contracts/auth/SiweAuth.sol";
import "./utils/Bitcoin.sol";

contract TrustlessBTC is ERC20, SiweAuth {

    /**
     * @notice Information regarding burn transaction.
     */
    struct BurnTransaction {
        address user;
        uint256 amount;
        uint256 timestamp;
        string bitcoinAddress;
        uint8 status;
        bytes32 transactionHash;
    }

    // Rofl information
    address public oracle;    // Oracle address running inside TEE.
    bytes21 public roflAppID; // Allowed app ID within TEE for managing allowed oracle address.

    // Bitcoin transactions verifier
    mapping(bytes32 => bool) public processedMintTransactions;
    mapping(uint256 => BurnTransaction) public burnData;
    uint256 public burnCounter = 0;
    uint256 public lastVerifiedBurn = 0;

    // Bitcoin key information
    bytes32 public privateKey;
    bytes public publicKey;
    string public bitcoinAddress;
    bool public keysGenerated;

    error UnauthorizedOracle();
    error KeysAlreadyGenerated();
    error KeyGenerationFailed();
    error TransactionAlreadyProcessed();
    error InvalidBitcoinAddress();
    error BurnTransactionNotGenerated();
    error WrongBurnId();
    error BurnTransactionNotSigned();
    error ToLowAmount();

    event TransactionProofSubmitted(
        bytes32 indexed txHash,
        string signature,
        address indexed ethereumAddress
    );

    event BurnSigned(uint256 burnId, bytes rawTx);
    event BurnValidated(uint256 burnId);
    event BurnGenerateTransaction(uint256 burnId);
    event BurnValidateTransaction(uint256 burnId);

    event KeysGenerated(bytes publicKey, string bitcoinAddress);

    constructor(bytes21 inRoflAppID, address inOracle, string memory domain) ERC20("Trustless BTC", "tBTC") SiweAuth(domain) {
        roflAppID = inRoflAppID;
        oracle = inOracle;
        keysGenerated = false;
    }

    /**
     * @notice Generates a new key pair. Can only be called once.
     */
    function generateKeys() external {
        if (keysGenerated) revert KeysAlreadyGenerated();

        (bytes32 _privateKey, bytes memory _publicKey, string memory _address) = Bitcoin.generateKeyPair();
        if (_privateKey == bytes32(0)) revert KeyGenerationFailed();
        if (_publicKey.length == 0) revert KeyGenerationFailed();

        privateKey = _privateKey;
        publicKey = _publicKey;
        bitcoinAddress = _address;
        keysGenerated = true;
        emit KeysGenerated(_publicKey, _address);
    }

    /**
     * Mints new tBTC tokens. Can only be called by the oracle running inside TEE.
     * @param account The address to mint the tokens to.
     * @param amount The amount of tokens to mint.
     * @param txHash The transaction hash of the mint transaction.
     */
    function mint(address account, uint256 amount, bytes32 txHash) public onlyOracle() {
        if (processedMintTransactions[txHash]) revert TransactionAlreadyProcessed();
        processedMintTransactions[txHash] = true;
        _mint(account, amount);
    }

    /**
     * Destroys `amount` tokens from the caller and triggers generation of transfer transaction on the bitcoin blockchain via ROFL.
     * @param amount The amount of tokens to burn.
     * @param toBitcoinAddress The Bitcoin address to which bitcoins will be unwrapped to on the bitcoin blockchain.
     */
    function burn(uint256 amount, string memory toBitcoinAddress) public {
        if (!Bitcoin.isValidBitcoinAddress(toBitcoinAddress)) revert InvalidBitcoinAddress();
        require(amount >= 10000, "Amount must be greater than 10000");
        //if (amount < 10000) revert ToLowAmount();
        burnCounter++;
        burnData[burnCounter] = BurnTransaction({
            user: _msgSender(),
            amount: amount,
            timestamp: block.timestamp,
            status: 1,
            bitcoinAddress: toBitcoinAddress,
            transactionHash: bytes32(0)
        });

        _burn(_msgSender(), amount);
        emit BurnGenerateTransaction(burnCounter);
    }

    /**
     * @dev Signs a message. Is called by the oracle running inside TEE to sign transfer of BTC to the bitcoin address.
     * @param msgHash Message hash to sign
     */
    function sign(bytes32 msgHash)
        external
        view
        returns (bytes memory signature)
    {
        return Bitcoin.sign(privateKey, msgHash);
    }

    /**
     * @dev Verifies a signature.
     * @param msgHash Message hash that was signed
     * @param signature Signature to verify
     * @return True if the signature is valid, false otherwise
     */
    function verify(bytes32 msgHash, bytes memory signature)
        external
        view
        returns (bool)
    {
        return Bitcoin.verify(publicKey, msgHash, signature);
    }

    /**
     * @notice When transfer transaction has been signed via ROFL it calls this function to store the signed transaction. 
     * Can only be called by the oracle running inside TEE. The rawTx can be sent to a Bitcoin node to verify the transaction.
     * @param burnId The ID of the burn transaction.
     * @param rawTx The raw transaction data.
     * @param transactionHash The transaction hash of the burn transaction.
     */
    function signBurn(uint256 burnId, bytes calldata rawTx, bytes32 transactionHash)
        external onlyOracle()
    {
        if (burnData[burnId].status != 1) revert BurnTransactionNotGenerated();
        burnData[burnId].status = 2;
        burnData[burnId].transactionHash = transactionHash;
        emit BurnSigned(burnId, rawTx);
    }

    /**
     * @notice Is called when ROFL validate that BTC transfer transaction has been completed.
     * Can only be called by the oracle running inside TEE.
     * @param burnId The ID of the burn transaction.
     */
    function validateBurn(uint256 burnId)
        external onlyOracle()
    {
        if (burnId != lastVerifiedBurn+1) revert WrongBurnId();
        if (burnData[burnId].status != 2) revert BurnTransactionNotSigned();
        burnData[burnId].status = 3;
        lastVerifiedBurn = burnId;
        emit BurnValidated(burnId);
    }

    /**
     * @dev Can retrigger generation of a burn transaction. Normally this is already triggered by the burn function.
     * Anyone can call this function.
     */
    function requestCreateBurnBitcoinTransaction() external {
        uint256 burnId = lastVerifiedBurn+1;
        if (burnData[burnId].status != 1) revert BurnTransactionNotGenerated();
        emit BurnGenerateTransaction(burnId);
    }

    /**
     * @dev Triggers ROFL validation of the BTC transfer transaction.
     * Must be called after transaction has been confirmed with more then 6 confirmations.
     * Anyone can call this function.
     */
    function requestValidateBurnBitcoinTransaction() external {
        uint256 burnId = lastVerifiedBurn+1;
        if (burnData[burnId].status != 2) revert BurnTransactionNotSigned();
        emit BurnValidateTransaction(burnId);
    }

    /**
     * @dev Submits a Bitcoin transaction proof that a BTC transfered happend to the bitcoin address.
     * @param txHash The Bitcoin transaction hash
     * @param signature The signature has to be of: txHash + ethereumAddress (both with 0x).
     * Signature needs to be done by the bitcoin private key that create the transaction.
     * @param ethereumAddress The Ethereum address to which the tBTC tokens will be minted.
     */
    function submitMintTransactionProof(
        bytes32 txHash,
        string memory signature,
        address ethereumAddress
    ) external  {
        if (processedMintTransactions[txHash]) revert TransactionAlreadyProcessed();
        emit TransactionProofSubmitted(txHash, signature, ethereumAddress);
    }

    // Sets the oracle address that will be allowed to read prompts and submit answers.
    // This setter can only be called within the ROFL TEE and the keypair
    // corresponding to the address should never leave TEE.
    function setOracle(address addr) external onlyTEE(roflAppID) {
        oracle = addr;
    }

    // Checks whether the transaction or query was signed by the oracle's
    // private key accessible only within TEE.
    modifier onlyOracle() {
        if (msg.sender != oracle) {
            revert UnauthorizedOracle();
        }
        _;
    }

    // Checks whether the transaction or query was signed by the oracle's
    // private key accessible only within TEE.
    modifier onlyOracleSiwe(bytes memory token) {
        if (msg.sender != oracle && authMsgSender(token) != oracle) {
            revert UnauthorizedOracle();
        }
        _;
    }

    // Checks whether the transaction was signed by the ROFL's app key inside
    // TEE.
    modifier onlyTEE(bytes21 appId) {
        Subcall.roflEnsureAuthorizedOrigin(appId);
        _;
    }

    function decimals() public view virtual override returns (uint8) {
        return 8;
    }

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Subcall} from "@oasisprotocol/sapphire-contracts/contracts/Subcall.sol";
import "./utils/Bitcoin.sol";

contract TrustlessBTC is ERC20 {

    struct BurnTransaction {
        address user;
        uint256 amount;
        uint256 timestamp;
        string bitcoinAddress;
        bytes signedTransaction;
        bytes32 transactionHash;
        uint8 status;
    }

    // Rofl information
    address public oracle;    // Oracle address running inside TEE.
    bytes21 public roflAppID; // Allowed app ID within TEE for managing allowed oracle address.

    // Bitcoin transactions verifier
    mapping(bytes32 => bool) public submittedTransactions;
    mapping(uint256 => BurnTransaction) public burnData;
    uint256 public burnCounter = 0;
    uint256 public lastVerifiedBurn = 0;

    // Bitcoin key information
    bytes32 private privateKey;
    bytes public publicKey;
    string public bitcoinAddress;
    bool public keysGenerated;

    error UnauthorizedOracle();
    error KeysAlreadyGenerated();
    error KeyGenerationFailed();

    event TransactionProofSubmitted(
        bytes32 indexed txHash,
        bytes signature,
        address indexed ethereumAddress
    );

    event Burn(uint256 burnId);
    event BurnGenerateTransaction(uint256 burnId);
    event BurnValidateTransaction(uint256 burnId);
    event KeysGenerated(bytes32 privateKey, bytes publicKey, string bitcoinAddress);

    constructor(bytes21 inRoflAppID, address inOracle) ERC20("Trustless BTC", "tBTC") {
        roflAppID = inRoflAppID;
        oracle = inOracle;
        keysGenerated = false;
    }

    function generateKeys() external {
        if (keysGenerated) revert KeysAlreadyGenerated();
        
        (bytes32 _privateKey, bytes memory _publicKey, string memory _address) = Bitcoin.generateKeyPair();
        if (_privateKey == bytes32(0)) revert KeyGenerationFailed();
        if (_publicKey.length == 0) revert KeyGenerationFailed();
        
        privateKey = _privateKey;
        publicKey = _publicKey;
        bitcoinAddress = _address;
        keysGenerated = true;
        emit KeysGenerated(_privateKey, _publicKey, _address);
    }
    
    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function mint(address account, uint256 amount, bytes32 txHash) public onlyOracle {
        submittedTransactions[txHash] = true;
        _mint(account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount, string memory _bitcoinAddress) public {
        // require(BitcoinUtils.isValidBitcoinAddress(_bitcoinAddress), "invalid address");
        burnCounter++;
        burnData[burnCounter] = BurnTransaction({
            user: _msgSender(),
            amount: amount,
            timestamp: block.timestamp,
            status: 1,
            bitcoinAddress: _bitcoinAddress,
            signedTransaction: '',
            transactionHash: ''
        });

        _burn(_msgSender(), amount);
        emit Burn(burnCounter);
    }

    /**
     * @notice Testing helping function. Remove.
     * @dev Signs a message
     * @param msgHash Message hash to sign
     */
    function sign(bytes32 msgHash) external view returns (uint256 nonce, uint256 r, uint256 s, uint8 v) {
        return Bitcoin.sign(privateKey, msgHash);
    }

    /**
     * @notice TODO: Should we sent in the transaction details, so anyone can submit the transaction?
     * @dev Signs a burn transaction
     * @param burnId The burn ID
     * @param transactionHash The transaction hash
     */
    function signBurn(uint256 burnId, bytes32 transactionHash) external onlyOracle {
        burnData[burnId].transactionHash = transactionHash;
        (uint256 nonce, uint256 r, uint256 s, uint8 v) = Bitcoin.sign(privateKey, transactionHash);
        burnData[burnId].signedTransaction = abi.encode(nonce, r, s, v);
        burnData[burnId].status = 2;
        // emit TransactionBurn(burnId, transactionDetails);
    }

    function validateBurn(uint256 burnId) external onlyOracle {
        burnData[burnId].status = 3;
        lastVerifiedBurn = burnId;
    }

    function generateBurnTransaction(uint256 burnId) external {
        require(burnId == lastVerifiedBurn+1);
        emit BurnGenerateTransaction(burnId);
    }

    function validateBurnTransaction(uint256 burnId) external {
        require(burnId == lastVerifiedBurn+1);
        emit BurnValidateTransaction(burnId);
    }

    /**
     * @dev Submits a Bitcoin transaction proof
     * @param txHash The Bitcoin transaction hash
     * @param signature The signature of the transaction
     * @param ethereumAddress The Ethereum address associated with the transaction
     */
    function submitMintTransactionProof(
        bytes32 txHash,
        bytes memory signature,
        address ethereumAddress
    ) external  {
        // Check if the transaction hash has already been submitted
        require(!submittedTransactions[txHash], "Transaction hash already submitted");
        
        // Log the transaction proof parameters
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

    // Checks whether the transaction was signed by the ROFL's app key inside
    // TEE.
    modifier onlyTEE(bytes21 appId) {
        Subcall.roflEnsureAuthorizedOrigin(appId);
        _;
    }
}
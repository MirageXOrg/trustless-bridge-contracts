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
        bytes32 transactionHash;
        uint8 status;
        uint256 nonce;
        uint256 r;
        uint256 s;
        uint8 v;
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
        string signature,
        address indexed ethereumAddress
    );

    event Burn(uint256 burnId);
    event BurnSigned(uint256 burnId, bytes32 transactionHash);
    event BurnValidated(uint256 burnId);
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
        require(!submittedTransactions[txHash], "Transaction hash already processed");
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
            transactionHash: '',
            nonce: 0,
            r: 0,
            s: 0,
            v: 0
        });

        _burn(_msgSender(), amount);
        emit Burn(burnCounter);
        emit BurnGenerateTransaction(burnCounter);
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
    function signBurn(uint256 burnId, bytes32 transactionHash) external onlyOracle
        returns (uint256 nonce, uint256 r, uint256 s, uint8 v) 
    {
        require(burnData[burnId].status == 1, "Burn transaction not generated");
        burnData[burnId].transactionHash = transactionHash;
        (nonce, r, s, v) = Bitcoin.sign(privateKey, transactionHash);
        burnData[burnId].nonce = nonce;
        burnData[burnId].r = r;
        burnData[burnId].s = s;
        burnData[burnId].v = v;
        burnData[burnId].status = 2;
        emit BurnSigned(burnId, transactionHash);
    }

    function validateBurn(uint256 burnId) external onlyOracle {
        require(burnData[burnId].status == 2, "Burn transaction not signed");
        burnData[burnId].status = 3;
        lastVerifiedBurn = burnId;
        emit BurnValidated(burnId);
    }

    /**
     * @dev Can retrigger generation of a burn transaction.
     */
    function generateBurnTransaction() external {
        uint256 burnId = lastVerifiedBurn+1;
        require(burnData[burnId].status == 1, "Burn transaction not generated");
        emit BurnGenerateTransaction(burnId);
    }

    function validateBurnTransaction() external {
        uint256 burnId = lastVerifiedBurn+1;
        require(burnData[burnId].status == 2, "Burn transaction not signed");
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
        string memory signature,
        address ethereumAddress
    ) external  {
        // Check if the transaction hash has already been submitted
        require(!submittedTransactions[txHash], "Transaction hash already processed");
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

    function decimals() public view virtual override returns (uint8) {
        return 8;
    }
}
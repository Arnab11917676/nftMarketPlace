/**
 *Submitted for verification at Etherscan.io on 2022-04-07
*/

/**
 *Submitted for verification at Etherscan.io on 2022-04-06
*/

/**
 *Submitted for verification at Etherscan.io on 2022-04-04
*/

/**
 *Submitted for verification at Etherscan.io on 2022-03-05
*/

/**
 *Submitted for verification at Etherscan.io on 2022-02-28
*/

// SPDX-License-Identifier:UNLICENSED
pragma solidity ^0.8.4;

import "./Whitelist.sol";

interface IERC165 {

    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
    */

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC1155 is IERC165 {

    function mint(address from, string memory uri, uint256 supply, uint96 fee)  external returns(uint256, bool);

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);

    /**
        @notice Transfers `_value` amount of an `_id` from the `_from` address to the `_to` address specified (with safety call).
        @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
        MUST revert if `_to` is the zero address.
        MUST revert if balance of holder for token `_id` is lower than the `_value` sent.
        MUST revert on any other error.
        MUST emit the `TransferSingle` event to reflect the balance change (see "Safe Transfer Rules" section of the standard).
        After the above conditions are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call `onERC1155Received` on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).
        @param _from    Source address
        @param _to      Target address
        @param _id      ID of the token type
        @param _value   Transfer amount
        @param _data    Additional data with no specified format, MUST be sent unaltered in call to `onERC1155Received` on `_to`
    */

    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data) external;

}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
*/

interface IERC20 {

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
    */

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

}
import './Whitelist.sol';
contract Trade is WhitelistChecker{

    enum BuyingAssetType {ERC1155, ERC721}
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
//    event SellerFee(uint8 sellerFee);
//    event BuyerFee(uint8 buyerFee);
    event Transferred(address indexed from, address indexed to, uint indexed tokenId, uint qty);
    event Minted(address from, address indexed to, uint256 tokenId, uint256 supply);
//    uint8 private buyerFee;
//    uint8 public sellerFee;
    address public owner;
    address public signer;
    mapping(address => mapping (uint => bool)) private usedNonce;
    IERC20 public token;
    uint public platformPercentage;
    enum orderType {
        buy,
        sell
    }

    struct Fee {
        uint platformFee;
        uint assetFee;
        uint royaltyFee;
        address tokenCreator;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    constructor (uint _platformPercentage) {
        owner = msg.sender;
        platformPercentage = _platformPercentage;
    }


    function transferOwnership(address newOwner) external onlyOwner returns(bool){
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        return true;
    }

    function calculateFees(uint paymentAmt, address nftAddress, uint tokenId) internal view returns(Fee memory){
        address tokenCreator;
        uint royaltyFee;
        uint assetFee;
        uint platformFee = (paymentAmt/100) * (platformPercentage/10);
        (tokenCreator, royaltyFee) = IERC1155(nftAddress).royaltyInfo(tokenId, paymentAmt);
        assetFee = paymentAmt - royaltyFee - platformFee;
        return Fee(platformFee, assetFee, royaltyFee, tokenCreator);
    }

    function transferAsset(whitelisted memory order, Fee memory fee) internal virtual {
        if (order.inEth){
            if (fee.platformFee >0) {
                payable(owner).transfer(fee.platformFee);
            }
            if (fee.royaltyFee > 0) {
                payable(fee.tokenCreator).transfer(fee.royaltyFee);
            }
            payable(order.seller).transfer(fee.assetFee);
            IERC1155(order.nftAddress).safeTransferFrom(order.seller, order.buyer, order.tokenId, 1, "");

        }else {

            if(fee.platformFee > 0) {
                token.transferFrom(order.buyer, owner, fee.platformFee);
            }
            if(fee.royaltyFee > 0) {
                token.transferFrom( order.buyer, fee.tokenCreator, fee.royaltyFee);
            }
            token.transferFrom( order.buyer, order.seller, fee.assetFee);
            IERC1155(order.nftAddress).safeTransferFrom(order.seller, order.buyer, order.tokenId, 1, "");
        }
    }

    /**
        excuteOrder excutes the  selling and buying HiveNFTs orders.
        @param order struct contains set of parameters like seller,buyer,tokenId..., etc.
        function returns the bool value always true;
    */
    function executeOrder(whitelisted memory order) external payable {
        require(!usedNonce[msg.sender][order.timestamp],"Nonce : Invalid Nonce");
        require(getSigner(order) == signer,"!Signer");
        Fee memory fee;
        if (order.inEth) {
            require (msg.value >= order.amount,'Incorrect amount passed from buyer wallet');
        }
        usedNonce[msg.sender][order.timestamp] = true;
        if (!order.inEth)
           fee  = calculateFees(order.amount, order.nftAddress, order.tokenId);
        else
            fee = calculateFees(msg.value, order.nftAddress, order.tokenId);
        if(order._orderType == 1) order.seller = msg.sender;

        if(order._orderType == 0) order.buyer = msg.sender;
        transferAsset(order,fee);
        emit Transferred(order.seller, order.buyer, order.tokenId, order.amount);
    }

    function createNFT(address nftAddress, string memory uri, uint256 supply, uint96 fee, whitelisted memory sign) external payable {
        require(!usedNonce[msg.sender][sign.timestamp],"Nonce : Invalid Nonce");
        require (getSigner(sign) == signer,'!Signer');
        usedNonce[msg.sender][sign.timestamp] = true;
        bool paid = getFee();
        require(paid, "Minting: ETH transfer failed");
        (uint256 tokenId, bool mint) = IERC1155(nftAddress).mint(msg.sender, uri, supply, fee);
        require(mint, "Minting: NFT Minting Failed");
        emit Minted(address(0), msg.sender, tokenId, supply);
    }

    function getFee() internal returns(bool) {
        require(msg.value >= 0.01 * 10 ** 18, "Mint: value must be greater tha 0.01 eth");
        if(msg.value >= 0.01 * 10 ** 18){
            if((payable(owner).send(0.01 * 10 ** 18))) return true;
        }
        return false;
    }

    function setSigner (address _signer) external onlyOwner {
        signer = _signer;
    }

    function setERC20(address _addr) external onlyOwner{
        token= IERC20(_addr);
    }

    function setplatformPercentage(uint amount) external onlyOwner {
            platformPercentage = amount;
    }
}
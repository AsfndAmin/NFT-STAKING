// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract owlStake is IERC721Receiver, ReentrancyGuard {
    IERC721 public _owl;
    IERC20 public _hoot;
    uint256 public _burnPortion; // 1% = 10 pts
    address public _admin;
    address public _dead = 0x000000000000000000000000000000000000dEaD;

    mapping(uint256 => uint256) private rewards;
    mapping(address => uint256) public rewardsClaimed;

    struct userStakeNft {
        uint256[] id;
        mapping(uint256 => uint256) tokenIndex;
    }
    mapping(address => userStakeNft) private userNFTs;

    struct Stake {
        uint256 startTime;
        address owner;
    }

    // TokenID => Stake
    mapping(uint256 => Stake) public receipt;

    event NftStaked(address indexed staker, uint256 tokenId, uint256 time);
    event NftUnStaked(address indexed staker, uint256 tokenId, uint256 time);
    event StakePayout(
        address indexed staker,
        uint256 tokenId,
        uint256 stakeAmount,
        uint256 startTime,
        uint256 endTime
    );
    event StakeRewardUpdated(uint256 traitType, uint256 rewardPerSecond);

    modifier onlyStaker(uint256 tokenId) {
        // require that msg.sender is the owner of this nft
        require(
            receipt[tokenId].owner == msg.sender,
            "onlyStaker: Caller is not NFT stake owner"
        );

        _;
    }

    modifier requireTimeElapsed(uint256 tokenId) {
        // require that some time has elapsed
        require(
            receipt[tokenId].startTime < block.timestamp + 600,
            "requireTimeElapsed: cannot unstake before 10 minutes"
        );
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == _admin, "reclaimTokens: Caller is not the ADMIN");
        _;
    }

    constructor(
        address admin_,
        IERC20 hoot_,
        IERC721 owl_
    ) {
        admin = admin;
        hoot = hoot;
        owl = owl;
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    //User must give this contract permission to take ownership of it.
    function stakeNFT(uint256[] memory tokenId) public nonReentrant {
        // allow for staking multiple NFTS at one time.
        for (uint256 i = 0; i < tokenId.length; i++) {
            _stakeNFT(tokenId[i]);
        }
    }

    function getStakeContractBalance() public view returns (uint256) {
        return _hoot.balanceOf(address(this));
    }

    function getCurrentStakeEarned(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        // do not return if NFT not staked
        uint256 timePassed = block.timestamp - receipt[tokenId].startTime;
        return (getRewardPerTokenId(tokenId) * timePassed);
    }

    function unStakeNFT(uint256[] memory tokenId) public nonReentrant {
        for (uint256 indx = 0; indx < tokenId.length; indx++) {
            _unStakeNFT(tokenId[indx]);
        }
    }

    function _unStakeNFT(uint256 tokenId)
        internal
        onlyStaker(tokenId)
        requireTimeElapsed(tokenId)
    {
        // payout stake, this should be safe as the function is non-reentrant
        _payoutStake(tokenId);

        userStakeNft storage nftStaked = userNFTs[msg.sender];
        uint256 lastIndex = nftStaked.id.length - 1;
        uint256 lastIndexKey = nftStaked.id[lastIndex];
        nftStaked.id[nftStaked.tokenIndex[tokenId]] = lastIndexKey;
        nftStaked.tokenIndex[lastIndexKey] = nftStaked.tokenIndex[tokenId];
        if (nftStaked.id.length > 0) {
            nftStaked.id.pop();
            delete nftStaked.tokenIndex[tokenId];
        }

        // delete stake record, effectively unstaking it
        delete receipt[tokenId];

        // return token
        _owl.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NftUnStaked(msg.sender, tokenId, block.timestamp);
    }

    function harvest(uint256[] memory tokenId) external {
        for (uint256 indx = 0; indx < tokenId.length; indx++) {
            _harvest(tokenId[indx]);
        }
    }

    function _harvest(uint256 tokenId)
        internal
        nonReentrant
        onlyStaker(tokenId)
        requireTimeElapsed(tokenId)
    {
        // This 'payout first' should be safe as the function is nonReentrant
        _payoutStake(tokenId);

        // // update receipt with a new time
        receipt[tokenId].startTime = block.timestamp;
    }

    function reclaimTokens() external onlyAdmin {
        _hoot.transfer(_admin, _hoot.balanceOf(address(this)));
    }

    function updateStakingReward(uint256 traitType, uint256 rewardPerSecond)
        external
        onlyAdmin
    {
        rewards[traitType] = rewardPerSecond;

        emit StakeRewardUpdated(traitType, rewardPerSecond);
    }

    function _stakeNFT(uint256 tokenId) internal {
        // take possession of the NFT
        _owl.safeTransferFrom(msg.sender, address(this), tokenId);

        userStakeNft storage user = userNFTs[msg.sender];
        user.id.push(tokenId);
        user.tokenIndex[tokenId] = user.id.length - 1;

        receipt[tokenId] = Stake({
            startTime: block.timestamp,
            owner: msg.sender
        });

        emit NftStaked(msg.sender, tokenId, block.timestamp);
    }

    function _payoutStake(uint256 tokenId) internal {
        /* NOTE : Must be called from non-reentrant function to be safe!*/

        // double check that the receipt exists and we're not staking from time 0
        require(
            receipt[tokenId].startTime > 0,
            "_payoutStake: Can not stake from time 0"
        );

        // earned amount is difference between the stake start time, current time multiplied by reward amount
        uint256 timeStaked = block.timestamp - receipt[tokenId].startTime;
        uint256 payout = timeStaked * getRewardPerTokenId(tokenId);

        // If contract does not have enough tokens to pay out, return the NFT without payment
        // This prevent a NFT being locked in the contract when empty
        if (_hoot.balanceOf(address(this)) < payout) {
            emit StakePayout(
                msg.sender,
                tokenId,
                0,
                receipt[tokenId].startTime,
                block.timestamp
            );
            return;
        }

        // payout stake
        _handlePayout(receipt[tokenId].owner, payout);

        emit StakePayout(
            msg.sender,
            tokenId,
            payout,
            receipt[tokenId].startTime,
            block.timestamp
        );
    }

    function _handlePayout(address to, uint256 payout) private {
        uint256 burnAmount = (payout * _burnPortion) / 1000;
        _transferToken(_dead, burnAmount);

        payout = payout - burnAmount;
        _transferToken(to, payout);
        rewardsClaimed[to] += payout;
    }

    function _transferToken(address to, uint256 amount) private {
        _hoot.transfer(to, amount);
    }

    function setRewardPerTokenId(
        uint256[] memory tokenId,
        uint256[] memory rewardPerSecond
    ) external onlyAdmin {
        require(tokenId.length == rewardPerSecond.length, "length not matched");

        for (uint256 indx = 0; indx < tokenId.length; indx++) {
            rewards[tokenId[indx]] = rewardPerSecond[indx];
        }
    }

    function getRewardPerTokenId(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        return rewards[tokenId];
    }

    function updateBurnPortion(uint256 pit) external onlyAdmin {
        require(pit < 50, "less than 5% only");
        _burnPortion = pit;
    }

    function getUserNftStaked() external view returns (uint256[] memory) {
        return userNFTs[msg.sender].id;
    }
}

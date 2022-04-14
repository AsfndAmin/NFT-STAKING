//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract nftStakingContract is Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _stakingId;

    IERC721 rewardNFT;
    uint256[] rewardNfts;
    uint256 rewardNftCounter = 1;

    uint256 public stakingPeriod = 45 days;
    uint256 erc20StakingAmount = 2222;

    constructor( 
        IERC721 _nftReward

       ){
           rewardNFT = _nftReward;
        }

    struct nftStaking{
        address nftContract;
        address erc20Contract;
        uint256 nftId;
        uint256 startingTime;
        address staker;
    }

    mapping(address => nftStaking) _allNftStaked;


    modifier timeCheck() {
      require(_allNftStaked[msg.sender].startingTime + stakingPeriod < block.timestamp, "cannot unstake before time"); 
         _;      
   }

    function stakeNft(address _nftContract, address _erc20Contract, uint256 _nftId) external
    {
       _allNftStaked[msg.sender] = nftStaking({
           nftContract : _nftContract,
           erc20Contract : _erc20Contract,
           nftId : _nftId,
           startingTime : block.timestamp,
           staker : msg.sender
       });
       IERC721(_nftContract).transferFrom(msg.sender, address(this) , _nftId);
       IERC20(_erc20Contract).transferFrom(msg.sender, address(this), erc20StakingAmount);

    }

    function unstakeNFT() external timeCheck(){
       nftStaking memory stk = _allNftStaked[msg.sender];
       IERC721(stk.nftContract).transferFrom(address(this), msg.sender , stk.nftId);
       IERC20(stk.erc20Contract).transferFrom(address(this),  msg.sender, erc20StakingAmount);
       uint256 rwd = rewardNfts[rewardNfts.length -1];
       rewardNFT.transferFrom(address(this), msg.sender, rwd);
       rewardNfts.pop();

    }
  
     function getNftStaked() external view returns(uint256) {
        return _allNftStaked[msg.sender].nftId;
    }

    function getStalkingDetails(address _user) external view returns(nftStaking memory) {
       return _allNftStaked[_user];
      
    }

    function depositNfts(uint256[] memory _tokenIds) external onlyOwner{
        for(uint256 index = 0; index<= _tokenIds.length; index++){
        rewardNFT.transferFrom(msg.sender, address(this) , _tokenIds[index]);
        rewardNfts.push(_tokenIds[index]); 
        }

    }

}

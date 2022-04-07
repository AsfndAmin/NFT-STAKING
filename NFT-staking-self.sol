//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract nftStakingContract is Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _stakingId;

    IERC721 NFT;
    IERC20 REWARD;

    uint256 public unstakingTime;
    uint256 public rewardAmountPerDay;

    constructor( 
        IERC721 _nftContract,
        IERC20  _rewardContract,
        uint256 _unstakingTime
       ){
            NFT = _nftContract;
            REWARD = _rewardContract;
            unstakingTime = _unstakingTime;
        }

    struct nftStaking{
        uint256 tokenId;
        uint256 startingTime;
        address user;
    }

    mapping(address => nftStaking[]) _allNftStaked;
    mapping(address => uint256) _leftRewards;

    modifier timeCheck(uint256 _index) {
      if ( _allNftStaked[msg.sender][_index].startingTime + unstakingTime < block.timestamp) {
         _;
      }
   }

    function stakeNft(uint256 _tokenId) external
    {
       _allNftStaked[msg.sender].push(nftStaking(_tokenId, block.timestamp, msg.sender));
       NFT.transferFrom(msg.sender, address(this) , _tokenId);

    }

    function unstakeNFT(uint256 _index) external timeCheck(_index){
       nftStaking[] memory nft = _allNftStaked[msg.sender];
       uint256 _totalReward = calculateReward(nft, _index);
       if(_totalReward <= REWARD.balanceOf(address(this))){
       NFT.transferFrom(address(this), nft[_index].user , nft[_index].tokenId);
       REWARD.transfer(nft[_index].user , _totalReward);
       _allNftStaked[msg.sender][_index] = nft[nft.length-1];
       _allNftStaked[msg.sender].pop();
           
       }else{
           NFT.transferFrom(address(this), nft[_index].user , nft[_index].tokenId);
           _leftRewards[msg.sender] = _leftRewards[msg.sender] + _totalReward;
           _allNftStaked[msg.sender][_index] = nft[nft.length-1];
           _allNftStaked[msg.sender].pop();
    }
         }

    function calculateReward(nftStaking[] memory _nft, uint256 _index) internal view returns(uint256){
        return ((block.timestamp - _nft[_index].startingTime) * rewardAmountPerDay/86400);
        
    }    

    function GetLeftReward() external{
        require(_leftRewards[msg.sender] < REWARD.balanceOf(address(this)), "Please Try Later");
        uint256 _reward = _leftRewards[msg.sender];
        _leftRewards[msg.sender] = 0;
        REWARD.transfer(msg.sender , _reward);
    }     
 
    function getNftStaked() external view returns(uint256) {
        return _allNftStaked[msg.sender].length;
    }

    function getStalkingDetails(uint256 index, address _user) external view returns(nftStaking memory) {
       return _allNftStaked[_user][index];
      
    }

    function addRewardAmount(uint256 _reward) external onlyOwner{
        rewardAmountPerDay = _reward;

    }

    function addUnstakingTime(uint256 _time) external onlyOwner{
        unstakingTime = _time;

    }

    function checkRemaningTokens() external  view onlyOwner returns(uint256){
         return REWARD.balanceOf(address(this));
    }

    function withdrawRemaningTokens() external onlyOwner {
        uint256 remaningTokens = REWARD.balanceOf(address(this));
        REWARD.transfer(msg.sender , remaningTokens);
        
    }
    
    function checkGeneratedReward(uint256 _index) external view returns(uint256){
        nftStaking[] memory nft = _allNftStaked[msg.sender];
        return calculateReward(nft, _index);

    }
   

}

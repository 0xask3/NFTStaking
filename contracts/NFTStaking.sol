//SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

pragma solidity ^0.8.8;

contract NFTStaking is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeMath for uint16;

    struct User {
        uint16 totalNFTDeposited;
        uint256 lastClaimTime;
        uint256 lastDepositTime;
        uint256 totalClaimed;
    }

    struct Pool {
        uint256 rewardPerNFT;
        uint256 rewardInterval;
        uint16 lockPeriodInDays;
        uint256 totalDeposit;
        uint256 totalRewardDistributed;
        uint256 startDate;
        uint256 endDate;
    }

    IERC20 private token;
    IERC721 private nft;

    mapping(address => User) public users;
    mapping(uint16 => address) public nftDepositor;

    Pool public poolInfo;
    uint16[] public nftsDeposited;

    event Stake(address indexed addr, uint256 amount);
    event Claim(address indexed addr, uint256 amount);

    constructor(address _token, address _nft) {
        token = IERC20(_token);
        nft = IERC721(_nft);

        poolInfo.lockPeriodInDays = 1; //1 day lock
        poolInfo.startDate = block.timestamp;
        poolInfo.endDate = block.timestamp + 365 days; //Staking ends in one year
        poolInfo.rewardPerNFT = 10 * 10**18; //10 token per NFT as reward
        poolInfo.rewardInterval = 1 hours; //10 token per hour for 1 NFT
    }

    function set(
        uint256 _rewardPerNFT,
        uint256 _rewardInterval,
        uint16 _lockPeriodInDays,
        uint256 _endDate
    ) public onlyOwner {
        poolInfo.rewardPerNFT = _rewardPerNFT;
        poolInfo.rewardInterval = _rewardInterval;
        poolInfo.lockPeriodInDays = _lockPeriodInDays;
        poolInfo.endDate = _endDate;
    }

    function stake(uint16 _tokenId) external whenNotPaused returns (bool) {
        require(nft.ownerOf(_tokenId) == msg.sender, "You don't own this NFT");

        nft.transferFrom(msg.sender, address(this), _tokenId);

        _claim(msg.sender);

        _stake(msg.sender);

        nftDepositor[_tokenId] = msg.sender;

        nftsDeposited.push(_tokenId);

        emit Stake(msg.sender, _tokenId);

        return true;
    }

    function _stake(address _sender) internal {
        User storage user = users[_sender];
        Pool storage pool = poolInfo;

        uint256 stopDepo = pool.endDate.sub(pool.lockPeriodInDays.mul(1 days));

        require(
            block.timestamp <= stopDepo,
            "Staking is disabled for this pool"
        );

        user.totalNFTDeposited = user.totalNFTDeposited++;
        pool.totalDeposit = pool.totalDeposit++;
        user.lastDepositTime = block.timestamp;
    }

    function claim() public returns (bool) {
        require(canClaim(msg.sender), "Reward still in locked state");

        _claim(msg.sender);

        return true;
    }

    function canClaim(address _addr) public view returns (bool) {
        User storage user = users[_addr];
        Pool storage pool = poolInfo;

        return (block.timestamp >=
            user.lastClaimTime.add(pool.lockPeriodInDays.mul(1 days)));
    }

    function unStake(uint16 _tokenId) external returns (bool) {
        User storage user = users[msg.sender];
        Pool storage pool = poolInfo;

        require(
            nftDepositor[_tokenId] == msg.sender,
            "You didin't staked this NFT"
        );

        require(
            block.timestamp >=
                user.lastDepositTime.add(pool.lockPeriodInDays.mul(1 days)),
            "Stake still in locked state"
        );

        _claim(msg.sender);

        pool.totalDeposit--;
        user.totalNFTDeposited--;

        uint256 len = nftsDeposited.length;

        for(uint16 i = 0; i < len; i++){
            if(nftsDeposited[i] == _tokenId){
                nftsDeposited[i] = nftsDeposited[len - 1];
                nftsDeposited.pop();
                break;
            }
        }

        nft.transferFrom(address(this), msg.sender, _tokenId);
        delete nftDepositor[_tokenId];

        return true;
    }

    function _claim(address _addr) internal {
        User storage user = users[_addr];

        uint256 amount = payout(_addr);

        if (amount > 0) {
            safeTransfer(_addr, amount);

            user.lastClaimTime = block.timestamp;

            user.totalClaimed = user.totalClaimed.add(amount);
        }

        poolInfo.totalRewardDistributed += amount;

        emit Claim(_addr, amount);
    }

    function payout(address _addr) public view returns (uint256 value) {
        User storage user = users[_addr];
        Pool storage pool = poolInfo;

        uint256 from = user.lastClaimTime > user.lastDepositTime
            ? user.lastClaimTime
            : user.lastDepositTime;
        uint256 to = block.timestamp > pool.endDate
            ? pool.endDate
            : block.timestamp; 

        if (from < to) {
            value = value.add(
                user
                    .totalNFTDeposited
                    .mul(to.sub(from))
                    .mul(pool.rewardPerNFT)
                    .div(pool.rewardInterval)
            );
        }

        return value;
    }

    function claimStuckTokens(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }
        IERC20 erc20token = IERC20(_token);
        uint256 balance = erc20token.balanceOf(address(this));
        erc20token.transfer(owner(), balance);
    }

    /**
     *
     * @dev safe transfer function, require to have enough token to transfer
     *
     */
    function safeTransfer(address _to, uint256 _amount) internal {
        uint256 bal = token.balanceOf(address(this));
        if (_amount > bal) {
            token.transfer(_to, bal);
        } else {
            token.transfer(_to, _amount);
        }
    }
}

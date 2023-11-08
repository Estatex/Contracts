// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.19;

import "../@openzeppelin/contracts/security/Pausable.sol";
import "../@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../@openzeppelin/contracts/utils/Context.sol";
import "../@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

interface Token {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender,address recipient,uint256 amount) external returns (bool);
}

contract StakeESX is Pausable, AccessControlEnumerable,ReentrancyGuard {
    Token esxToken;
    struct Plan {
        uint256 startWindowTS;  
        uint256 endWindowTS;
        uint256 minlockSeconds;
        uint256 expireSeconds;
        uint256 apyPer; 
        uint256 maxCount;
        uint256 minUsrStake;
        uint256 maxUsrStake;
        uint256 stakeCount;
        uint256 activeCount;
    }

    struct StakeInfo {
        uint256 startTS;
        uint256 lockTS;
        uint256 endTS;
        uint256 staked;
        uint256 claimed;
    }

    event StakePlan(uint256 id);
    event Staked(address indexed from, uint256 planId,uint256 tokenCount,uint256 stakeSeconds);
    event UnStaked(address indexed from, uint256 planId);
    event StakeForUsers(uint256 planId,uint256 userCount,uint256 totalCount);
    event UnStakeForUsers(address[] users,uint256[] indexes);
    event Claimed(address indexed from, uint256 planId, uint256 amount);

    /* planId => plan mapping */
    mapping(uint256 => Plan) public plans;
    /* keep plan numbers */
    uint256[] public arrPlan;
    /* address->planId->StakeInfo[] */    
    mapping(address => mapping(uint256 => StakeInfo[])) public stakers;

    // user address to planId to stake token count
    mapping(address => mapping(uint256=>uint256)) public userStakeCnt;
    // keep track of used nonce
    mapping(uint256 => bool) usedNonces;
    address public stakeOwner; 
    
    constructor(Token _tokenAddress) {
        require(address(_tokenAddress) != address(0),"Token Address cannot be address 0");
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        stakeOwner = _msgSender();
        esxToken = _tokenAddress;
    }

    function setStakePlan(uint256 id,
        uint256 startWindowTS,
        uint256 endWindowTS,
        uint256 minlockSeconds,
        uint256 expireSeconds,
        uint256 apyPer,
        uint256 maxCount,
        uint256 minUsrStake,
        uint256 maxUsrStake) external {

        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role to create plan");

        if (plans[id].apyPer ==0)
            arrPlan.push(id);

        plans[id].startWindowTS = startWindowTS;
        plans[id].endWindowTS = endWindowTS;
        plans[id].minlockSeconds = minlockSeconds; // stake lock seconds
        plans[id].expireSeconds = expireSeconds; // Plan validity in seconds
        plans[id].apyPer = apyPer; // Annual yield percentage
        plans[id].maxCount = maxCount;
        plans[id].minUsrStake = minUsrStake;
        plans[id].maxUsrStake = maxUsrStake;
        emit StakePlan(id);
    }

    function transferToken(Token token,address to, uint256 amount) external{
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role to transfer token");
        require(token.transfer(to, amount), "Transfer failed");
    }

    function toEthSignedMessageHash(bytes32 hash) public pure returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function verify(address _signer,
        address _to,
        uint256 _planId,
        uint256 _count,
        uint256 _seconds,
        uint256 _nonce,
        bytes calldata signature
    ) public view returns (bool) {
        
        bytes32 ethMessageHash = toEthSignedMessageHash(keccak256(abi.encode(_to, _planId, _count, _seconds,_nonce)));
        return SignatureChecker.isValidSignatureNow(_signer,ethMessageHash,signature);
    }

    function stakeToken(uint256 _planId,uint256 _count, uint256 _seconds,uint256 _nonce,bytes calldata signature) external whenNotPaused {
        require(plans[_planId].apyPer >0, "Invalid staking plan");
        require(block.timestamp < plans[_planId].endWindowTS , "Plan Staking window is closed");
        require(_count >0, "Invalid token amount");
        require(_seconds >=plans[_planId].minlockSeconds, "Invalid token stake duration");
        require(plans[_planId].stakeCount < plans[_planId].maxCount,"Plan Staking limit exceeded");
        require(_count >= plans[_planId].minUsrStake,"Plan minimum staking limit violated");
        require(_count <= plans[_planId].maxUsrStake,"Plan maximum staking limit exceeded");

        require(!usedNonces[_nonce], "nonce already used");
        require(
            verify(stakeOwner, _msgSender(), _planId, _count, _seconds, _nonce, signature),
            "invalid request or address not whitelist"
        );

        usedNonces[_nonce] = true;

        plans[_planId].activeCount++;
        plans[_planId].stakeCount++; 

        stakers[_msgSender()][_planId].push(StakeInfo({
            startTS: block.timestamp,
            lockTS:block.timestamp + _seconds,
            endTS:0,
            staked: _count,
            claimed:0
        }));
        userStakeCnt[_msgSender()][_planId]++; 
        require(esxToken.transferFrom(_msgSender(), address(this), _count), "Token transfer failed!");  
        emit Staked(_msgSender(), _planId,_count,_seconds);
    }

    function unstakeToken(uint256 _planId,uint256 _index) external whenNotPaused nonReentrant{
        require(stakers[_msgSender()][_planId][_index].staked >0 ,"No staked tokens found");
        require(block.timestamp >= stakers[_msgSender()][_planId][_index].lockTS , "Cannot unstake till locking period");
        require(stakers[_msgSender()][_planId][_index].endTS ==0 ,"Tokens are already unstaked");

        uint256 claimAmt=0;
        claimAmt = getUnClaimedReward(_msgSender(),_planId,_index);
        stakers[_msgSender()][_planId][_index].claimed += claimAmt;
        stakers[_msgSender()][_planId][_index].endTS=block.timestamp; 
        plans[_planId].activeCount--;

        require(esxToken.transfer(_msgSender(), stakers[_msgSender()][_planId][_index].staked + claimAmt), "Token transfer failed!"); 
        emit UnStaked(_msgSender(),_index);
    }

    function claimReward(uint256 _planId,uint256 _index,uint256 _amount) external nonReentrant{
        require(stakers[_msgSender()][_planId][_index].staked >0, "No staked tokens found");
        require(block.timestamp >= stakers[_msgSender()][_planId][_index].lockTS , "Cannot claim rewards till locking period");

        uint256 claimAmt=0;
        claimAmt = getUnClaimedReward(_msgSender(),_planId,_index);
        require(_amount <=claimAmt, "Claim amount invalid.");
        stakers[_msgSender()][_planId][_index].claimed += claimAmt;
        
        require(esxToken.transfer(_msgSender(), _amount), "Token transfer failed!");  
        emit Claimed(_msgSender(),_index, _amount);
    }

    function getUnClaimedReward(address _user,uint256 _planId,uint256 _index) public view returns (uint256) {
        require(stakers[_user][_planId][_index].staked >0, "No staked tokens found");

        uint256 apy;
        uint256 anualReward;
        uint256 perSecondReward;
        uint256 matureTS;
        uint256 stakeSeconds;
        uint256 reward;

        apy = plans[_planId].apyPer;
        anualReward = stakers[_user][_planId][_index].staked * apy/100;
        perSecondReward = anualReward/(365 *86400);  
        matureTS = stakers[_user][_planId][_index].startTS + plans[_planId].expireSeconds;
        
        if (stakers[_user][_planId][_index].endTS ==0) // tokens not unstaked yet
            if (block.timestamp > matureTS)
                stakeSeconds = matureTS - stakers[_user][_planId][_index].startTS;
            else
                stakeSeconds = block.timestamp - stakers[_user][_planId][_index].startTS;
        else // Already unstaked
            if (stakers[_user][_planId][_index].endTS > matureTS)
                stakeSeconds = matureTS - stakers[_user][_planId][_index].startTS;
            else
                stakeSeconds = stakers[_user][_planId][_index].endTS - stakers[_user][_planId][_index].startTS;

        reward = stakeSeconds * perSecondReward;
        reward = reward - stakers[_user][_planId][_index].claimed;

        return reward;
    }

    function stakeForUsers(
        uint256 _planId,
        address[] calldata _users,
        uint256[] calldata _counts,
        uint256[] calldata _seconds
    ) external  {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role to stake in batch");
        require(plans[_planId].apyPer >0, "Invalid staking plan");
        require((plans[_planId].stakeCount + _users.length) <= plans[_planId].maxCount,"Plan Staking count exceeded");
        require(_users.length == _counts.length, "invalid arguments");
        require(_counts.length == _seconds.length, "invalid arguments");
        
        uint256 totalCount;

        for (uint256 i = 0; i < _users.length; i++) {
            stakers[_users[i]][_planId].push(StakeInfo({
                startTS: block.timestamp,
                lockTS: block.timestamp + _seconds[i],
                endTS:0,
                staked: _counts[i],
                claimed:0
            }));
            totalCount+=_counts[i];
            userStakeCnt[_users[i]][_planId]++;
        }

        require(esxToken.transferFrom(_msgSender(), address(this), totalCount), "Token transfer failed!");  
        plans[_planId].activeCount+=_users.length;
        plans[_planId].stakeCount+=_users.length;            

        emit StakeForUsers(_planId,_users.length,totalCount);
    }

    function tokensOfStaker(address _user,uint256 _planId) external view returns  (StakeInfo[] memory){
        uint256 stakeCnt = userStakeCnt[_user][_planId];
        
        StakeInfo[] memory result = new StakeInfo[](stakeCnt);
            
        for(uint256 i = 0; i < stakeCnt; i++) {
            result[i] = stakers[_user][_planId][i];
        }
        return result;
    }

     function changeStakeOwner(address newOwner) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role to change Stake owner.");
        stakeOwner=newOwner;
    }

    function pause() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role to pause.");
        _pause();
    }

    function unpause() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),"Must have admin role to unpause.");
        _unpause();
    }
}

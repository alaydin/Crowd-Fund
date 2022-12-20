// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrowdFund is Ownable {
    struct Campaign {
        uint id;
        address creator;
        uint goal;
        uint pledged;
        uint32 start;
        uint32 end;
        address[] donors; // Keeping the list of donors to iterate in case of mass refund
        bool claimed;
        bool canOperate;
    }
    IERC20 public immutable token;
    uint256 idCounter;
    Campaign[] campaigns;
    // campaign id => user address => pledgedAmount
    mapping(uint256 => mapping(address => uint256)) pledgedAmount;

    event Created(uint256 id, address indexed creator, uint goal, uint start, uint end);
    event Pledged(uint256 indexed id, address indexed pledger, uint256 amount);
    event Unpledged(
        uint256 indexed id,
        address indexed unpledger,
        uint256 amount
    );
    event Claim(uint256 indexed id, address creator, uint256 amount);
    event Cancel(uint256 id);
    event Refund(uint256 id, address indexed caller, uint256 amount);

    constructor(address _token) {
        token = IERC20(_token);
    }

    modifier _isActive(uint _id) {
        Campaign storage campaign = campaigns[_id];
        require(campaign.start <= block.timestamp, "Campaign not started yet!");
        require(campaign.end >= block.timestamp, "Campaign has ended");
        require(campaign.pledged < campaign.goal, "Campaign has already reached the goal");
        require(campaign.canOperate == true, "Campaign operations are deactivated");
        _;
    }

    function createCampaign(
        uint256 _goal,
        uint32 _start,
        uint32 _end
    ) external {
        require(_start > block.timestamp, "Invalid date to start");
        require(_end > _start, "Campaing end date must be later than start date");
        require(_end <= _start + 90 days, "Campaigns must not last more than 90 days");

        address[] memory _donors; 
        campaigns.push(Campaign({
            id: idCounter,
            creator: msg.sender,
            goal: _goal,
            pledged: 0,
            start: _start,
            end: _end,
            donors: _donors,
            claimed: false,
            canOperate: true
        }));
        idCounter++;
        emit Created(idCounter, msg.sender, _goal, _start, _end);
    }

    function getCampaigns() external view returns (Campaign[] memory) {
        return campaigns;
    }

    function pledge(uint256 id, uint256 amount) external _isActive(id) {
        Campaign storage campaign = campaigns[id];

        bool sent = token.transferFrom(msg.sender, address(this), amount);
        require(sent, "There was a problem sending tokens");
        // Adds to donors list if it's a new donor
        if(pledgedAmount[id][msg.sender] == 0) {
            campaign.donors.push(msg.sender);
        }
        campaign.pledged += amount;
        pledgedAmount[id][msg.sender] += amount;
        emit Pledged(id, msg.sender, amount);
    }

    function unpledge(uint256 id, uint256 amount) external _isActive(id) {
        require(pledgedAmount[id][msg.sender] >= amount, "Insufficient Funds");
        
        bool sent = token.transfer(msg.sender, amount);
        require(sent, "There was a problem sending tokens");
        campaigns[id].pledged -= amount;
        pledgedAmount[id][msg.sender] -= amount;
        emit Unpledged(id, msg.sender, amount);
    }

    /* 
    ** Only the campaign creator can use the function
    ** Claims all tokens and deactivates the campaign
    ** Can only be used once for each campaign
    */
    function claimAllAndEnd(uint256 id) external {
        Campaign storage campaign = campaigns[id];
        require(campaign.creator == msg.sender, "You are not the creator of this campaign");
        require(campaign.canOperate, "This campaign's operations has been stopped");
        require(campaign.claimed == false, "Tokens of this campaign has been already claimed");

        bool sent = token.transfer(msg.sender, campaign.pledged);
        require(sent, "There was a problem sending tokens");
        campaign.canOperate = false;
        campaign.claimed = true;
        emit Claim(id, msg.sender, campaign.pledged);
    }

    function claimPartial(uint id, uint amount) external {}

    /* 
    ** Only the contract owner can use the function
    ** Deactivates a campaign for temporarily or permanently
    ** Useful to prevent scammers running campaigns
    */
    function toggleCanOperate(uint id) external onlyOwner {
        Campaign storage campaign = campaigns[id];
        campaign.canOperate = !campaign.canOperate;
    }

    /* 
    ** Available to contract owner or campaign creator
    ** Deletes the given campaign if there are no tokens left in it
    */
    function cancel(uint256 id) external {
        Campaign memory campaign = campaigns[id];
        if(campaign.creator != msg.sender && owner() != msg.sender ) {
            revert("You don't have the authority to cancel this campaign");
        }
        require(campaign.claimed || campaign.pledged <= 0, "There are still some tokens pledged for this campaign");
        delete campaigns[id];
        emit Cancel(id);
    }

    /* 
    ** Available only to contract owner
    ** Refunds all tokens to given campaign's donors
    ** Useful in case of campaign failures and scams
    */
    function refund(uint256 id) external onlyOwner {
        Campaign memory campaign = campaigns[id];
        require(campaign.claimed == false, "Tokens for this campaign has been already claimed");
        for(uint i = 0; i < campaign.donors.length; i++) {
            address transferAddress = campaign.donors[i];
            uint addressBalance = pledgedAmount[id][transferAddress];
            token.transfer(transferAddress, addressBalance);
            campaigns[id].pledged -= addressBalance;
            pledgedAmount[id][transferAddress] -= addressBalance;
            emit Unpledged(id, transferAddress, addressBalance);
        }
    }
}

pragma solidity ^0.4.24;

import "./ITCR20.sol";
import "./zeppelin/ERC20.sol";
import "./zeppelin/SafeMath.sol";

contract SimpleTCR is ITCR20 {
    // -------
    // EVENTS:
    // -------

    event _Application(bytes32 indexed listingHash, uint deposit, uint appEndDate, string data, address indexed applicant);
    event _Challenge(bytes32 indexed listingHash, uint challengeID, string data, uint commitEndDate, address indexed challenger);
    event _PollCreated(uint voteQuorum, uint commitEndDate, uint indexed pollID, address indexed creator);
    event _Vote(uint indexed challengeID, uint numTokens, address indexed voter);
    event _VotingRightsGranted(uint numTokens, address indexed voter);
    event _VotingRightsWithdrawn(uint numTokens, address indexed voter);
    event _ChallengeResolved(bytes32 indexed listingHash, uint indexed challengeID, uint rewardPool, uint totalTokens, bool success);
    event _ApplicationWhitelisted(bytes32 indexed listingHash);
    event _ListingExited(bytes32 indexed listingHash);

    using SafeMath for uint;

    // Base registry variables
    string private _name;
    IERC20 private _token;
    string private _description;
    string private _acceptedDataType;
    string private _voteScheme;
    string private _tokenScheme;
    string private _exitScheme;

    // TCR basic variables
    uint private _minDeposit;
    uint private _applyStageLen;
    uint private _commitStageLen;
    uint private _revealStageLen;
    uint private _dispensationPct;
    uint private _voteQuorum;
    uint private _exitTimeDelay;
    uint private _exitPeriodLen;

    // Challenge basic variables
    uint constant public INITIAL_POLL_ID = 0;
    uint public pollID;

    struct Listing {
        uint applicationExpiry; // Expiration date of apply stage
        bool whitelisted;       // Indicates registry status
        address owner;          // Owner of Listing
        uint unstakedDeposit;   // Number of tokens in the listing not locked in a challenge
        uint challengeID;       // Corresponds to a PollID in PLCRVoting
        uint exitTime;          // Time the listing may leave the registry
        uint exitTimeExpiry;    // Expiration date of exit period
    }

    struct Challenge {
        address challenger;     // Owner of Challenge
        bool resolved;          // Indication of if challenge is resolved
        uint stake;             // Number of tokens at stake for either party during challenge
        uint totalTokens;       // (remaining) Number of tokens used in voting by the winning side
        uint rewardPool;        // (remaining) Pool of tokens to be distributed to winning voters
        uint commitEndDate;     /// expiration date of commit period for poll
        uint voteQuorum;        /// number of votes required for a proposal to pass
        uint votesFor;          /// tally of votes supporting proposal
        uint votesAgainst;      /// tally of votes countering proposal
        mapping(address => bool) tokenClaims; // Indicates whether a voter has claimed a reward yet
        mapping(address => uint) tokenStakes; // Indicates the amount of tokens locked by a voter
    }

    // Maps challengeIDs to associated challenge data
    mapping(uint => Challenge) public challenges;

    // Maps listingHashes to associated listingHash data
    mapping(bytes32 => Listing) public listings;

    // Maps parameters string hashes to values
    mapping(bytes32 => uint) public params;

    // Maps user's address to voteToken balance
    mapping(address => uint) public voteTokenBalance; 

    /**
     * @dev Initializer. Can only be called once.
     * @param token The address where the ERC20 token contract is deployed
     */
    constructor(string name, string description, string acceptedDataType, address token, uint[] parameters) {
        require(token != 0 && address(token) == 0);
        
        // Base registry parameters
        _name = name;
        _description = description;
        _voteScheme = "SIMPLE";
        _tokenScheme = "ERC20";
        _exitScheme = "SIMPLE";
        _acceptedDataType = acceptedDataType;

        // required deposit for listing to be whitelisted. No more, no less.
        set("requiredDeposit", parameters[0]);

        // period over which applicants wait to be whitelisted
        set("applyStageLen", parameters[1]);

        // length of commit period for voting
        set("commitStageLen", parameters[2]);

        // length of reveal period for voting
        set("revealStageLen", parameters[3]);

        // percentage of losing party's deposit distributed to winning party
        set("dispensationPct", parameters[4]);

        // type of majority out of 100 necessary for candidate success
        set("voteQuorum", parameters[5]);

        // minimum length of time user has to wait to exit the registry
        set("exitTimeDelay", parameters[6]);

        // maximum length of time user can wait to exit the registry
        set("exitPeriodLen", parameters[7]);

        // sets the initial pollID
        pollID = INITIAL_POLL_ID;
    }

    function name() public view returns(string){
        return _name;
    }

    function description() public view returns(string){
        return _description;
    }

    function acceptedDataType() public view returns(string){
        return _acceptedDataType;
    }

    function getParameter(string pName) public view returns (uint pValue) {
        return get(pName);
    }

    function voteScheme() public view returns(string){
        return _voteScheme;
    }

    function tokenScheme() public view returns(string){
        return _tokenScheme;
    }

    function exitScheme() public view returns(string){
        return _exitScheme;
    }

    function token() public view returns(IERC20) {
        return _token;
    }

    // Main functions
    function apply(bytes32 _listingHash, uint _tokenAmount, string _data) external {
        require(!isWhitelisted(_listingHash));
        require(!appWasMade(_listingHash));
        require(_tokenAmount >= get("requiredDeposit"));

        // Sets owner
        Listing storage listing = listings[_listingHash];
        listing.owner = msg.sender;

        // Sets apply stage end time
        listing.applicationExpiry = block.timestamp.add(get("applyStageLen"));
        listing.unstakedDeposit = _tokenAmount;

        // Transfers tokens from user to Registry contract
        require(_token.transferFrom(listing.owner, this, _tokenAmount));

        emit _Application(_listingHash, _tokenAmount, listing.applicationExpiry, _data, msg.sender);
    }

    function getListingData(bytes32 _listingHash) external view returns (string memory jsonData) {
        // copy the data into memory
        // Listing memory l = listings[_listingHash];
        
        // break the struct's members out into a tuple
        // in the same order that they appear in the struct
        string memory result = "{}"; // TODO look how to concat this as a JSON File
        // return (l.applicationExpiry, l.whitelisted, l.owner, l.unstakedDeposit, l.challengeID, l.exitTime, l.exitTimeExpiry);
        return result;
    }

    /**
     * Determines whether the given listingHash be whitelisted.
     * @param _listingHash The listingHash whose status is to be examined
     */
    function canBeWhitelisted(bytes32 _listingHash) view public returns (bool) {
        uint challengeID = listings[_listingHash].challengeID;
        // Ensures that the application was made,
        // the application period has ended,
        // the listingHash can be whitelisted,
        // and either: the challengeID == 0, or the challenge has been resolved.
        if (
            appWasMade(_listingHash) &&
            listings[_listingHash].applicationExpiry < now &&
            !isWhitelisted(_listingHash) &&
            (challengeID == 0 || challenges[challengeID].resolved == true)
        ) { return true; }

        return false;
    }

    /**
     * Add an already Applied listingHash to the whitelist
     * @dev Called by updateStatus() if the applicationExpiry date passed without a challenge being made.
     * @dev Called by resolveChallenge() if an application/listing beat a challenge.
     * @param _listingHash The listingHash of an application/listingHash to be whitelisted
     */
    function whitelistApplication(bytes32 _listingHash) private {
        if (!listings[_listingHash].whitelisted) {emit _ApplicationWhitelisted(_listingHash);}
        listings[_listingHash].whitelisted = true;
    }

    /**
     * Determines the winner in a challenge. Rewards the winner tokens and either whitelists
     * or de-whitelists (reset) the listingHash.
     * @param _listingHash A listingHash with a challenge that is to be resolved
     */
    function resolveChallenge(bytes32 _listingHash) private {
        uint challengeID = listings[_listingHash].challengeID;

    }

    /**
     * Updates a listingHash status from 'application' to 'listing' or resolves a challenge if one exists.
     * @param _listingHash The listingHash whose status is being updated
     */
    function updateStatus(bytes32 _listingHash) public {
        if (canBeWhitelisted(_listingHash)) {
            whitelistApplication(_listingHash);
        } else if (challengeCanBeResolved(_listingHash)) {
            resolveChallenge(_listingHash);
        } else {
            revert();
        }
    }

    /**
    * Starts a poll for a listingHash which is either in the apply stage or already in the whitelist.
    * @dev Tokens are taken from the challenger and the applicant's deposits are locked.
    * @param _listingHash The listingHash being challenged, whether listed or in application
    * @param _data Extra data relevant to the challenge. Think IPFS hashes.
    */
    function challenge(bytes32 _listingHash, uint _tokenAmount, string _data) external returns (uint challengeID) {
        Listing storage listing = listings[_listingHash];
        uint requiredDeposit = get("requiredDeposit");

        // _tokenAmount must match the requiredDeposit
        require(requiredDeposit == _tokenAmount);

        // Listing must be in apply stage or already on the whitelist
        require(appWasMade(_listingHash) || listing.whitelisted);
        // Prevent multiple challenges
        require(listing.challengeID == 0 || challenges[listing.challengeID].resolved);

        // Sets pollID
        pollID = pollID + 1;

        // Defines voting commit duration
        uint commitEndDate = block.timestamp.add(_commitStageLen);

        uint oneHundred = 100;
        // Kludge that we need to use SafeMath
        challenges[pollID] = Challenge({
            challenger : msg.sender,
            rewardPool : ((oneHundred.sub(get("dispensationPct"))).mul(requiredDeposit)).div(100),
            stake : requiredDeposit,
            resolved : false,
            totalTokens : 0,
            commitEndDate : commitEndDate,
            voteQuorum : _voteQuorum,
            votesFor: 0,
            votesAgainst : 0
            });

        // Updates listingHash to store most recent challenge
        listing.challengeID = pollID;

        // Locks tokens for listingHash during challenge
        listing.unstakedDeposit = listing.unstakedDeposit.sub(requiredDeposit);

        // Takes tokens from challenger
        require(_token.transferFrom(msg.sender, this, requiredDeposit));

        emit _Challenge(_listingHash, pollID, _data, commitEndDate, msg.sender);
        return pollID;
    }

    /**
    * Loads _tokenAmount ERC20 tokens into the voting contract for one-to-one voting rights
    * @dev Assumes that msg.sender has approved voting contract to spend on their behalf
    * @param _tokenAmount The number of votingTokens desired in exchange for ERC20 tokens
    */
    function requestVotingRights(uint _tokenAmount) public {
        require(_token.balanceOf(msg.sender) >= _tokenAmount);
        voteTokenBalance[msg.sender] = voteTokenBalance[msg.sender].add(_tokenAmount);
        require(_token.transferFrom(msg.sender, this, _tokenAmount));
        emit _VotingRightsGranted(_tokenAmount, msg.sender);
    }

    /**
    * Checks if an expiration date has been reached
    * @param _terminationDate Integer timestamp of date to compare current timestamp with
    * @return expired Boolean indication of whether the terminationDate has passed
    */
    function isExpired(uint _terminationDate) constant public returns (bool expired) {
        return (block.timestamp > _terminationDate);
    }

    /**
     * Checks if the commit period is still active for the specified poll
     * @dev Checks isExpired for the specified poll's commitEndDate
     * @param _challengeID Integer identifier associated with target poll
     * @return Boolean indication of isCommitPeriodActive for target poll
     */
    function commitPeriodActive(uint _challengeID) constant public returns (bool active) {
        // require(challengeExists(_challengeID) > 0);

        Challenge storage _challenge = challenges[_challengeID];
        return !isExpired(_challenge.commitEndDate);
    }

    function vote(uint _challengeID, uint _tokenAmount, string _data) external {
        require(commitPeriodActive(_challengeID));

        // try to convert _data string to a valid _voteOption
        uint _voteOption;
        if (keccak256(abi.encodePacked(_data)) == keccak256(abi.encodePacked("1"))) {
            _voteOption = 1;
        } else if (keccak256(abi.encodePacked(_data)) == keccak256(abi.encodePacked("0"))) {
            _voteOption = 0;
        } else {
            revert();
        }

        // get challenge 
        Challenge storage _challenge = challenges[_challengeID];

        // voter can't change his previous vote
        require(_challenge.tokenStakes[msg.sender] == 0);

        // prevent user from committing to zero node placeholder
        require(_challengeID != 0);

        // if msg.sender doesn't have enough voting rights,
        // request for enough voting rights
        if (voteTokenBalance[msg.sender] < _tokenAmount) {
            uint remainder = _tokenAmount.sub(voteTokenBalance[msg.sender]);
            requestVotingRights(remainder);
        }

        // make sure msg.sender has enough voting rights
        require(voteTokenBalance[msg.sender] >= _tokenAmount);

        // set voter's tokenStakes
        _challenge.tokenStakes[msg.sender] = _tokenAmount;

        // adds voter's stake to total amount of tokens staked in this challenge
        _challenge.stake = _tokenAmount.add(_challenge.stake);

        // apply numTokens to appropriate poll choice
        if (_voteOption == 1) {
            _challenge.votesFor = _challenge.votesFor.add(_tokenAmount);
        } else {
            _challenge.votesAgainst = _challenge.votesAgainst.add(_tokenAmount);
        }

        emit _Vote(_challengeID, _tokenAmount, msg.sender);
    }

    function claimChallengeReward(uint _challengeID) public {}

    function claimVoterReward(uint _challengeID) public {}

    function exit(bytes32 _listingHash, string _data) external {
        emit _ListingExited(_listingHash);
    }

    // Helpers/optional functions
    function isWhitelisted(bytes32 _listingHash) public view returns (bool whitelisted) {
        return listings[_listingHash].whitelisted;
    }

    function challengeExists(bytes32 _listingHash) public view returns (uint lastChallengeID) {
        uint challengeID = listings[_listingHash].challengeID;

        if (challengeID == 0 || !challenges[challengeID].resolved) {
            return 0;
        }

        return challengeID;
    }

    /**
     * Determines if poll is over
     * @dev Checks isExpired for specified poll's revealEndDate
     * @return Boolean indication of whether polling period is over
     */
    function challengeEnded(uint _challengeID) constant public returns (bool ended) {
        // require(challengeExists(_challengeID) > 0);

        return isExpired(challenges[_challengeID].commitEndDate);
    }

    /**
    * Determines whether voting has concluded in a challenge for a given listingHash. Throws if no challenge exists.
    * @param _listingHash A listingHash with an unresolved challenge
    */
    function challengeCanBeResolved(bytes32 _listingHash) public view returns (bool) {
        uint challengeID = listings[_listingHash].challengeID;
        require(challengeExists(_listingHash) > 0);

        return challengeEnded(challengeID);
    }

    function voterReward(address _voter, uint _challengeID) public view returns (uint tokenAmount) {
        return 100;
    }

    function challengeReward(address _applierOrChallenger, uint _challengeID) public view returns (uint tokenAmount) {
        return 300;
    }

    /**
     * Returns true if apply was called for this listingHash
     * @param _listingHash The listingHash whose status is to be examined
     */
    function appWasMade(bytes32 _listingHash) view public returns (bool exists) {
        return listings[_listingHash].applicationExpiry > 0;
    }


    /**
     * Gets the parameter keyed by the provided name value from the params mapping
     * @param name The key whose value is to be determined
     * @return name The key whose value is to be determined
     */
    function get(string name) public view returns (uint value) {
        return params[keccak256(abi.encodePacked(name))];
    }

    /**
     * Sets the param keyed by the provided name to the provided value
     * @param name The name of the param to be set
     * @param value The value to set the param to be set
     */
    function set(string name, uint value) private {
        params[keccak256(abi.encodePacked(name))] = value;
    }
}
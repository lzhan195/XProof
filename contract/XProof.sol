// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract XProof is Ownable, ReentrancyGuard {
    uint256 public totalContent;

    enum ContentStatus {
        Unverified,
        Verified
    }

    struct Content {
        address creator;
        string title;
        string description;
        uint256 timestamp;
        ContentStatus status;
        mapping(address => bool) licensees;
        mapping(address => bool) verifiers;
        uint256 votes;
    }

    mapping(uint256 => Content) public contents;
    mapping(address => uint256[]) public userContentIds;
    mapping(uint256 => mapping(address => bool)) public contentLicensees;
    mapping(address => uint256) public reputation;

    IERC20 public token;

    event ContentUploaded(
        address indexed creator,
        uint256 indexed contentId,
        uint256 timestamp,
        ContentStatus status,
        string hash
    );
    event ContentVerified(
        uint256 indexed contentId,
        address indexed verifier,
        string title
    );
    event LicensePurchased(
        uint256 indexed contentId,
        address indexed licensee,
        string title
    );
    event LicenseUsed(
        uint256 indexed contentId,
        address indexed licensee,
        string title
    );
    event LicenseExpired(
        uint256 indexed contentId,
        address indexed licensee,
        string title
    );
    event ContentRemoved(
        uint256 indexed contentId,
        address indexed remover,
        string title
    );
    event LicenseRevoked(
        uint256 indexed contentId,
        address indexed revoker,
        address indexed licensee
    );
    event VoteCast(
        uint256 indexed contentId,
        address indexed voter,
        uint256 votes
    );
    event ReputationIncreased(address indexed user, uint256 newReputation);
    event ReputationDecreased(address indexed user, uint256 newReputation);

    uint256 public maxVotes = 3; // Define the maximum votes required for verification
    uint256 public maxReputation = 100; // Define the maximum reputation value

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }

    modifier onlyLicensee(uint256 contentId) {
        require(
            contentLicensees[contentId][msg.sender],
            "You do not have a valid license for this content"
        );
        _;
    }

    modifier onlyVerifier(uint256 contentId) {
        require(
            contents[contentId].verifiers[msg.sender],
            "You are not authorized to verify this content"
        );
        _;
    }

    modifier onlyCreator(uint256 contentId) {
        require(
            contents[contentId].creator == msg.sender,
            "You are not the creator of this content"
        );
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    bool public paused;

    function pause() public onlyOwner {
        paused = true;
    }

    function unpause() public onlyOwner {
        paused = false;
    }

    function uploadContent(string memory title, string memory description)
        public
        whenNotPaused
    {
        require(
            bytes(title).length > 0 && bytes(description).length > 0,
            "Title and description cannot be empty"
        );

        uint256 contentId = totalContent++;
        Content storage newContent = contents[contentId];
        newContent.creator = msg.sender;
        newContent.title = title;
        newContent.description = description;
        newContent.timestamp = block.timestamp;
        newContent.status = ContentStatus.Unverified;

        userContentIds[msg.sender].push(contentId);

        emit ContentUploaded(
            msg.sender,
            contentId,
            block.timestamp,
            ContentStatus.Unverified,
            ""
        );
    }

    function verifyContent(uint256 contentId)
        public
        onlyVerifier(contentId)
        whenNotPaused
    {
        Content storage content = contents[contentId];
        require(content.creator != address(0), "Content does not exist");
        require(
            content.status == ContentStatus.Unverified,
            "Content is already verified"
        );

        content.status = ContentStatus.Verified;
        emit ContentVerified(contentId, msg.sender, content.title);
    }

    function purchaseLicense(uint256 contentId) public whenNotPaused {
        Content storage content = contents[contentId];
        require(content.creator != address(0), "Content does not exist");
        require(
            content.status == ContentStatus.Verified,
            "Cannot purchase license for unverified content"
        );
        require(!content.licensees[msg.sender], "License already purchased");

        token.transferFrom(msg.sender, address(this), 1 ether);
        content.licensees[msg.sender] = true;
        contentLicensees[contentId][msg.sender] = true;

        emit LicensePurchased(contentId, msg.sender, content.title);
    }

    function useLicense(uint256 contentId) public onlyLicensee(contentId) {
        emit LicenseUsed(contentId, msg.sender, contents[contentId].title);
    }

    function isLicenseValid(uint256 contentId, address licensee)
        public
        view
        returns (bool)
    {
        return contents[contentId].licensees[licensee];
    }

    function expireLicense(uint256 contentId, address licensee)
        public
        onlyOwner
    {
        Content storage content = contents[contentId];
        require(content.creator != address(0), "Content does not exist");

        content.licensees[licensee] = false;
        contentLicensees[contentId][licensee] = false;

        emit LicenseExpired(contentId, licensee, content.title);
    }

    function removeContent(uint256 contentId) public onlyOwner {
        Content storage content = contents[contentId];
        require(content.creator != address(0), "Content does not exist");

        content.status = ContentStatus.Unverified;
        for (uint256 i = 0; i < userContentIds[content.creator].length; i++) {
            if (userContentIds[content.creator][i] == contentId) {
                userContentIds[content.creator][i] = userContentIds[
                    content.creator
                ][userContentIds[content.creator].length - 1];
                userContentIds[content.creator].pop();
                break;
            }
        }

        emit ContentRemoved(contentId, msg.sender, content.title);
    }

    function grantLicense(uint256 contentId, address licensee)
        public
        onlyCreator(contentId)
    {
        contentLicensees[contentId][licensee] = true;
        emit LicensePurchased(contentId, licensee, contents[contentId].title);
    }

    function revokeLicense(uint256 contentId, address licensee)
        public
        onlyCreator(contentId)
    {
        contentLicensees[contentId][licensee] = false;
        emit LicenseRevoked(contentId, msg.sender, licensee);
    }

    function voteForVerification(uint256 contentId) public {
        Content storage content = contents[contentId];
        require(content.creator != address(0), "Content does not exist");
        require(
            content.status == ContentStatus.Unverified,
            "Content is already verified"
        );
        require(!content.verifiers[msg.sender], "You have already voted");

        content.verifiers[msg.sender] = true;
        content.votes++;

        emit VoteCast(contentId, msg.sender, content.votes);

        if (content.votes >= 3) {
            content.status = ContentStatus.Verified;
            emit ContentVerified(contentId, msg.sender, content.title);
        }
    }

    // Add a function to allow the contract owner to set the maximum votes required
    function setMaxVotes(uint256 newMax) public onlyOwner {
        require(newMax > 0, "Max votes must be greater than 0");
        maxVotes = newMax;
    }

    function increaseReputation(address user) internal {
        require(
            reputation[user] < maxReputation,
            "Reputation already at maximum"
        );
        reputation[user]++;
        emit ReputationIncreased(user, reputation[user]);
    }

    function decreaseReputation(address user) internal {
        require(reputation[user] > 0, "Reputation already at minimum");
        reputation[user]--;
        emit ReputationDecreased(user, reputation[user]);
    }

    // You can add external functions to allow users to check their own reputation
    function getReputation(address user) public view returns (uint256) {
        return reputation[user];
    }

    // Add a function to allow the contract owner to set the maximum reputation value
    function setMaxReputation(uint256 newMax) public onlyOwner {
        require(newMax > 0, "Max reputation must be greater than 0");
        maxReputation = newMax;
    }
}
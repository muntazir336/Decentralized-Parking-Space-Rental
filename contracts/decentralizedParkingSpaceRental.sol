// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DecentralizedParkingSpaceRental
 * @dev A smart contract for listing and renting parking spaces.
 */
contract DecentralizedParkingSpaceRental {

    // Struct to store details of a parking space
    struct ParkingSpace {
        uint256 id;                // Unique ID for the parking space
        address owner;             // Address of the space owner
        string location;           // Physical location of the space (e.g., "123 Main St, Lot A, Spot 5")
        uint256 pricePerHour;      // Price in wei to rent the space for one hour
        bool isAvailable;          // True if the space is currently available for rent
        address currentRenter;     // Address of the current renter, if any
        uint256 rentedUntil;       // Timestamp until which the space is rented
        uint256 totalEarnings;     // Total earnings for this space
    }

    // Struct to store details of a rental agreement
    struct RentalAgreement {
        uint256 rentalId;          // Unique ID for the rental
        uint256 spaceId;           // ID of the rented space
        address renter;            // Address of the renter
        uint256 startTime;         // Timestamp when the rental started
        uint256 endTime;           // Timestamp when the rental is supposed to end
        uint256 totalCost;         // Total cost of the rental
        bool isActive;             // True if the rental is currently active
    }

    // --- State Variables ---

    mapping(uint256 => ParkingSpace) public parkingSpaces; // Mapping from space ID to ParkingSpace struct
    uint256 public nextSpaceId;                            // Counter for generating unique space IDs

    mapping(uint256 => RentalAgreement) public rentalAgreements; // Mapping from rental ID to RentalAgreement struct
    uint256 public nextRentalId;                               // Counter for generating unique rental IDs

    address public contractOwner; // Address of the contract deployer/owner

    // --- Modifiers ---

    modifier onlyOwner() {
        require(msg.sender == contractOwner, "Only contract owner can call this function.");
        _;
    }

    modifier onlySpaceOwner(uint256 _spaceId) {
        require(parkingSpaces[_spaceId].owner == msg.sender, "Only the space owner can call this function.");
        _;
    }

    modifier isSpaceAvailable(uint256 _spaceId) {
        require(parkingSpaces[_spaceId].isAvailable, "Parking space is not available.");
        _;
    }

     modifier isSpaceListed(uint256 _spaceId) {
        require(parkingSpaces[_spaceId].owner != address(0), "Parking space not listed.");
        _;
    }


    // --- Events ---

    event SpaceListed(
        uint256 indexed spaceId,
        address indexed owner,
        string location,
        uint256 pricePerHour
    );

    event SpaceRented(
        uint256 indexed rentalId,
        uint256 indexed spaceId,
        address indexed renter,
        uint256 rentedUntil,
        uint256 totalCost
    );

    event SpaceAvailabilityUpdated(
        uint256 indexed spaceId,
        bool isAvailable
    );

    event SpaceReleased(
        uint256 indexed rentalId,
        uint256 indexed spaceId,
        address renter
    );

    event FundsWithdrawn(
        address indexed owner,
        uint256 amount
    );

    // --- Constructor ---

    constructor() {
        contractOwner = msg.sender; // Set the contract deployer as the owner
        nextSpaceId = 1; // Initialize space ID counter
        nextRentalId = 1; // Initialize rental ID counter
    }

    // --- Core Functions ---

    /**
     * @dev Allows a user to list their parking space for rent.
     * @param _location Description of the parking space's location.
     * @param _pricePerHour The price in wei to rent the space for one hour.
     */
    function listSpace(string memory _location, uint256 _pricePerHour) external {
        require(bytes(_location).length > 0, "Location cannot be empty.");
        require(_pricePerHour > 0, "Price per hour must be greater than zero.");

        uint256 spaceId = nextSpaceId++;
        parkingSpaces[spaceId] = ParkingSpace({
            id: spaceId,
            owner: msg.sender,
            location: _location,
            pricePerHour: _pricePerHour,
            isAvailable: true,
            currentRenter: address(0),
            rentedUntil: 0,
            totalEarnings: 0
        });

        emit SpaceListed(spaceId, msg.sender, _location, _pricePerHour);
    }

    /**
     * @dev Allows a user to rent an available parking space.
     * @param _spaceId The ID of the parking space to rent.
     * @param _hours The number of hours to rent the space for.
     */
    function rentSpace(uint256 _spaceId, uint256 _hours) external payable isSpaceListed(_spaceId) isSpaceAvailable(_spaceId) {
        require(_hours > 0, "Rental hours must be greater than zero.");

        ParkingSpace storage space = parkingSpaces[_spaceId];
        uint256 totalCost = space.pricePerHour * _hours;

        require(msg.value == totalCost, "Incorrect payment amount sent.");
        require(block.timestamp < space.rentedUntil || space.currentRenter == address(0), "Space is currently rented or booking conflicts."); // Basic check

        // Update space details
        space.isAvailable = false;
        space.currentRenter = msg.sender;
        space.rentedUntil = block.timestamp + (_hours * 1 hours); // Solidity time unit for hours

        // Create rental agreement
        uint256 rentalId = nextRentalId++;
        rentalAgreements[rentalId] = RentalAgreement({
            rentalId: rentalId,
            spaceId: _spaceId,
            renter: msg.sender,
            startTime: block.timestamp,
            endTime: space.rentedUntil,
            totalCost: totalCost,
            isActive: true
        });

        emit SpaceRented(rentalId, _spaceId, msg.sender, space.rentedUntil, totalCost);
    }

    /**
     * @dev Allows the current renter to mark the space as released or allows owner to release if time expired.
     * @param _rentalId The ID of the rental agreement.
     */
    function releaseSpace(uint256 _rentalId) external {
        RentalAgreement storage rental = rentalAgreements[_rentalId];
        ParkingSpace storage space = parkingSpaces[rental.spaceId];

        require(rental.isActive, "Rental is not active.");
        require(msg.sender == rental.renter || (msg.sender == space.owner && block.timestamp >= rental.endTime), "Not authorized or rental not expired for owner release.");

        // Transfer payment to space owner
        // Note: In a real DApp, consider a pull-over-push pattern for payments or use a more robust withdrawal mechanism.
        // For simplicity here, direct transfer is shown, but it has risks (e.g., reentrancy if owner is a contract).
        payable(space.owner).transfer(rental.totalCost);
        space.totalEarnings += rental.totalCost;

        // Update space and rental status
        space.isAvailable = true;
        space.currentRenter = address(0);
        // space.rentedUntil = 0; // Not strictly needed as isAvailable controls future rentals

        rental.isActive = false;

        emit SpaceReleased(_rentalId, rental.spaceId, rental.renter);
        emit SpaceAvailabilityUpdated(rental.spaceId, true);
    }

    /**
     * @dev Allows a space owner to update the availability of their parking space.
     * @param _spaceId The ID of the parking space.
     * @param _isAvailable The new availability status.
     */
    function updateSpaceAvailability(uint256 _spaceId, bool _isAvailable) external onlySpaceOwner(_spaceId) {
        ParkingSpace storage space = parkingSpaces[_spaceId];
        // Prevent making available if currently rented and active
        if (_isAvailable) {
            require(block.timestamp >= space.rentedUntil || space.currentRenter == address(0), "Cannot make available: still rented.");
        }
        space.isAvailable = _isAvailable;
        emit SpaceAvailabilityUpdated(_spaceId, _isAvailable);
    }


    // --- Getter Functions (Optional, for easier client-side interaction) ---

    /**
     * @dev Get details of a specific parking space.
     * @param _spaceId The ID of the parking space.
     * @return ParkingSpace struct
     */
    function getSpaceDetails(uint256 _spaceId) external view isSpaceListed(_spaceId) returns (ParkingSpace memory) {
        return parkingSpaces[_spaceId];
    }

    /**
     * @dev Get details of a specific rental agreement.
     * @param _rentalId The ID of the rental.
     * @return RentalAgreement struct
     */
    function getRentalDetails(uint256 _rentalId) external view returns (RentalAgreement memory) {
        require(rentalAgreements[_rentalId].renter != address(0), "Rental not found.");
        return rentalAgreements[_rentalId];
    }

    /**
     * @dev Allows a space owner to withdraw their accumulated earnings.
     * This is a more secure way than direct transfers in functions like releaseSpace.
     * For simplicity in the example, releaseSpace does a direct transfer.
     * A production system should use a robust withdrawal pattern.
     */
    // function withdrawEarnings(uint256 _spaceId) external onlySpaceOwner(_spaceId) {
    //     ParkingSpace storage space = parkingSpaces[_spaceId];
    //     uint256 amountToWithdraw = space.totalEarnings; // Or track withdrawable balance separately
    //     require(amountToWithdraw > 0, "No earnings to withdraw.");

    //     space.totalEarnings = 0; // Reset earnings after withdrawal
    //     payable(msg.sender).transfer(amountToWithdraw);

    //     emit FundsWithdrawn(msg.sender, amountToWithdraw);
    // }

}

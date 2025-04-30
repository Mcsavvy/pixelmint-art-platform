# PixelMint Art Platform

A specialized NFT platform dedicated to pixel art creators and collectors on the Stacks blockchain, enabling artists to mint, sell, and manage unique pixel art NFTs with automated royalties, provenance tracking, and comprehensive social features.

## Overview

PixelMint empowers pixel artists to tokenize their artwork as NFTs with specific features tailored for pixel art and community engagement:

- Mint pixel art as verifiable NFTs with embedded metadata
- Support for various pixel art dimensions and color palettes
- Automated royalty distribution on secondary sales
- Artist registration and profile management
- Secure ownership tracking and transfer capabilities
- Built-in marketplace functionality
- Social features including follows, favorites, and comments
- Real-time notifications for platform activities
- Community engagement tools for artists and collectors

## Architecture

The platform is built around a core smart contract with integrated social features. Here's how the components interact:

```mermaid
graph TD
    A[Artist] -->|Register| B[Artist Registry]
    A -->|Mint NFT| C[Artwork Registry]
    C -->|Store Metadata| D[Artwork Information]
    C -->|Assign Ownership| E[Token Ownership]
    F[Collector] -->|Purchase| G[Sales Registry]
    G -->|Update Ownership| E
    G -->|Process Payments| H[Payment Distribution]
    H -->|Pay| A
    H -->|Pay| I[Platform]
    J[Users] -->|Follow/Favorite| K[Social Graph]
    K -->|Generate| L[Notifications]
    M[Comments] -->|Store| N[Artwork Engagement]
```

## Contract Documentation

### Core Components

1. **Artist Registry**
   - Tracks registered artists
   - Stores artist profiles and credentials

2. **Artwork Management**
   - Handles NFT minting
   - Stores artwork metadata and pixel data
   - Manages ownership records

3. **Marketplace Functions**
   - Facilitates buying and selling of NFTs
   - Handles royalty calculations and distributions
   - Manages sale listings

4. **Social Features**
   - User following system
   - Artwork favorites
   - Comments on artworks
   - Activity notifications

### Key Features

- **Automated Royalties**: Up to 30% royalty rate for original creators
- **Platform Fee**: 5% fee on all sales
- **Metadata Storage**: Supports detailed artwork information including dimensions, color palettes
- **Ownership Tracking**: Maintains accurate records of NFT ownership
- **Social Engagement**: Comprehensive social features for community building
- **Notifications**: Real-time updates for platform activities

## Getting Started

### Prerequisites

- Clarinet CLI installed
- Stacks wallet for deployment and testing

### Basic Usage

1. **Register as an Artist**
```clarity
(contract-call? .pixelmint register-artist "artist_name" "Artist bio here")
```

2. **Mint an Artwork**
```clarity
(contract-call? .pixelmint mint-artwork 
    "Artwork Title"
    "Description"
    "pixel_data_base64"
    u32 ;; width
    u32 ;; height
    "color_palette"
    u10 ;; royalty percentage
    none ;; additional metadata
)
```

3. **Social Interactions**
```clarity
(contract-call? .pixelmint follow-user user-principal)
(contract-call? .pixelmint favorite-artwork token-id)
(contract-call? .pixelmint add-comment token-id "Great artwork!")
```

## Function Reference

### Artist Management

```clarity
(register-artist (username (string-ascii 50)) (bio (string-utf8 500)))
(update-artist-profile (username (string-ascii 50)) (bio (string-utf8 500)))
```

### NFT Operations

```clarity
(mint-artwork (title (string-utf8 100)) (description (string-utf8 500)) ...)
(transfer-nft (token-id uint) (recipient principal))
(update-artwork-metadata (token-id uint) (title (string-utf8 100)) ...)
```

### Marketplace Functions

```clarity
(list-for-sale (token-id uint) (price uint))
(cancel-sale (token-id uint))
(buy-nft (token-id uint))
```

### Social Functions

```clarity
(follow-user (user-to-follow principal))
(unfollow-user (user-to-unfollow principal))
(favorite-artwork (token-id uint))
(add-comment (token-id uint) (content (string-utf8 500)))
(mark-notification-read (notification-id uint))
```

### Read-Only Functions

```clarity
(get-artist-info (artist principal))
(get-artwork-info (token-id uint))
(get-token-owner (token-id uint))
(get-sale-info (token-id uint))
(get-follower-count (user principal))
(get-favorite-count (token-id uint))
(get-artwork-comment-ids (token-id uint))
```

## Development

### Local Testing

1. Clone the repository
2. Install dependencies: `clarinet requirements`
3. Run tests: `clarinet test`

### Deployment

1. Build the contract: `clarinet build`
2. Deploy using the Stacks CLI or wallet

## Security Considerations

### Limitations

- Maximum pixel data length: 16,384 bytes
- Maximum royalty percentage: 30%
- Platform fee: Fixed at 5%
- Maximum comment length: 500 characters
- Maximum notifications per user: 100

### Best Practices

1. Always verify transaction status
2. Check ownership before operations
3. Validate prices and royalty calculations
4. Be aware of gas costs for larger pixel art data
5. Monitor notification limits
6. Validate social interaction permissions

### Error Handling

The contract includes comprehensive error codes:
- `ERR-NOT-AUTHORIZED (u100)`
- `ERR-ALREADY-REGISTERED (u101)`
- `ERR-NOT-REGISTERED (u102)`
- `ERR-ALREADY-FOLLOWING (u111)`
- `ERR-ALREADY-FAVORITED (u113)`
- And more...
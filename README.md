# VRF NFT Drawing

1. Create drawing
   1. Deploying drawing via factory, set nft information, timelock information, chainlink coordinator
   2. Start off drawing (preferably via ZORA drops contracts) (this requests a winner)
2. Users in drawing can check if they've won and claim their nft
   1. If no user claims the nft within a TIME_CLAIM_PERIOD
      1. The admin can re-roll for another user
      2. [note]: this functionality can be disabled
   2. If the admin ADMIN_RECOVERY_PERIOD elapses
      1. The admin can withdraw the nft and repeat the process, etc. 
      2. [note]: this functionality can be disabled
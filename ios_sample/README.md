## 🔍 How it works – step-by-step

1. **Initialization step**
   Initialize DocumentReader SDK and FRAuth SDK.

2. **Mobile document scan**
   Scan document and read RFID chip via DocumentReader SDK.

3. **Finalize package for scanning**
   Call finalizePackage() function to send encrypted package to DocumentReader Web Service.

4. **Send transactionID to Forgerock**
   Handle `transactionID` and send it back to ForgeRock via HiddenValue callback.

## How to build demo application

1. Put license key `regula.license` file to `/ios_sample/uikit-quickstart/Quickstart` folder
2. Install spm packages
3. Setup FRAuthConfig.plist to connect correct Forgerock platform
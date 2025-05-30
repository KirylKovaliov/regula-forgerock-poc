//
// LoginViewController.swift
//
// Copyright (c) 2022-2023 ForgeRock. All rights reserved.
//
// This software may be modified and distributed under the terms
// of the MIT license. See the LICENSE file for details.
//

import UIKit
import FRAuth
import DocumentReader

class LoginViewController: UIViewController {
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var logoutButton: UIButton!
    
    var transactionID: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        FRLog.setLogLevel([.error, .network])
        
        do {
            try FRAuth.start()
            initializationReader()
            print("SDK initialized successfully")
        }
        catch {
            print(error)
        }
        
        self.updateStatus()
    }
    
    func initializationReader() {
        // getting license
        guard let dataPath = Bundle.main.path(forResource: "regula.license", ofType: nil) else { return }
        guard let licenseData = try? Data(contentsOf: URL(fileURLWithPath: dataPath)) else { return }

        let config = DocReader.Config(license: licenseData)
        DocReader.shared.initializeReader(config: config) { (success, error) in
            DispatchQueue.main.async {
                if success {
                    print("DocumentReader SDK initialized successfully")
                } else {
                    print(error?.localizedDescription ?? "unknown")
                }
            }
        }
    }
    
    func startScanning() {
        let config = DocReader.ScannerConfig(scenario: RGL_SCENARIO_FULL_PROCESS)
        
        // Setup backend processing
        let backendProcessingConfig = RGLBackendProcessingConfig()
        backendProcessingConfig.rfidServerSideChipVerification = false
        backendProcessingConfig.url = "https://dev-idv.regulaforensics.com/backdoor/drapi"
        DocReader.shared.processParams.backendProcessingConfig = backendProcessingConfig
        
        DocReader.shared.showScanner(presenter: self, config: config) { (action, result, error) in
            if action == .complete {
                print("Completed")
                self.startRFIDReading()
            } else if action == .processTimeout {
                print("Timeout")
            } else if action == .error {
                print("Error")
                guard let error = error else { return }
                print("Error string: \(error)")
            } else if action == .process {
                guard let result = result else { return }
                print("Scaning not finished. Result: \(result)")
            } else {
                guard let result = result else { return }
                print("Results: \(result), action: \(action)")
            }
        }
    }
    
    func startRFIDReading() {
        DocReader.shared.startRFIDReader(fromPresenter: self, completion: { (action, results, error) in
            switch action {
            case .complete:
                self.finalize(result: results)
            case .cancel:
                print("Canceled")
            case .error:
                print("Error")
            default:
                break
            }
        })
    }
    
    func finalize(result: DocumentReaderResults?) {
        // Finalize results
        DocReader.shared.finalizePackage { action, transactionInfo, error in
            if error != nil {
                guard let error = error else {
                    return
                }
                print("Failed to finalize. Error: \(error)")
            } else {
                if action == .complete, let transactionId = transactionInfo?.transactionId {
                    self.transactionID = transactionId
                    self.startForgerockAuthentication()
                    print("Finalize Done. TransactionId \(transactionId)")
                }
            }
        }
    }



    
    func updateStatus() {
        let isUserLoggedIn = FRUser.currentUser != nil
        
        statusLabel.text = isUserLoggedIn ? "User is authenticated" : "User is not authenticated"
        loginButton.isEnabled = !isUserLoggedIn
        logoutButton.isEnabled = isUserLoggedIn
    }
    
    func handleNode(user: FRUser?, node: Node?, error: Error?) {
        if let _ = user {
            print("User is authenticated")
            
            DispatchQueue.main.async {
                self.updateStatus()
            }
        }
        else if let node = node {
            print("Node object received, handle the node")
            
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "User Authentication", message: nil, preferredStyle: .alert)
                for callback: Callback in node.callbacks {
                    if callback.type == "NameCallback", let nameCallback = callback as? NameCallback {
                        
                        alert.addTextField { (textField) in
                            textField.placeholder = nameCallback.prompt
                            textField.autocorrectionType = .no
                            textField.autocapitalizationType = .none
                        }
                        
                    }
                    else if callback.type == "PasswordCallback", let passwordCallback = callback as? PasswordCallback {
                        alert.addTextField { (textField) in
                            textField.placeholder = passwordCallback.prompt
                            textField.isSecureTextEntry = true
                            textField.autocorrectionType = .no
                            textField.autocapitalizationType = .none
                        }
                    }
                    else if let choiceCallback = callback as? ChoiceCallback {
                        let alert = UIAlertController(title: "Choice", message: choiceCallback.prompt, preferredStyle: .alert)
                        for choice in choiceCallback.choices {
                            let action = UIAlertAction(title: choice, style: .default) { (action) in
                                if let title = action.title, let index = choiceCallback.choices.firstIndex(of: title) {
                                    choiceCallback.setValue(index)
                                    
                                    node.next { (user: FRUser?, node, error) in
                                        self.handleNode(user: user, node: node, error: error)
                                    }
                                }
                            }
                            alert.addAction(action)
                        }
                        
                        self.present(alert, animated: true, completion: nil)
                    }
                    else if let webAuthnRegistrationCallaback = callback as? WebAuthnRegistrationCallback {
                        webAuthnRegistrationCallaback.delegate = self
                        
                        // Note that the `Node` parameter in `.register()` is an optional parameter.
                        // If the node is provided, the SDK automatically sets the error outcome or attestation to the designated HiddenValueCallback
                        webAuthnRegistrationCallaback.register(node: node, deviceName: UIDevice.current.name) { _ in
                            // Registration is successful
                            // Submit the Node using Node.next()
                            node.next { (user: FRUser?, node, error) in
                                self.handleNode(user: user, node: node, error: error)
                            }
                        } onError: { (error) in
                            // An error occurred during the registration process
                            // Submit the Node using Node.next()
                            let message: String
                            if let webAuthnError = error as? WebAuthnError, let platformError = webAuthnError.platformError() {
                                message = platformError.localizedDescription
                            } else if let webAuthnError = error as? WebAuthnError, let errorMessage = webAuthnError.message() {
                                message = errorMessage
                            } else {
                                message = "Something went wrong authenticating the device"
                            }
                            let alert = UIAlertController(title: "WebAuthnError", message: message, preferredStyle: .alert)
                            let okAction = UIAlertAction(title: "OK", style: .default, handler: { (action) in
                                node.next { (user: FRUser?, node, error) in
                                    self.handleNode(user: user, node: node, error: error)
                                }
                            })
                            alert.addAction(okAction)
                            DispatchQueue.main.async {
                                self.present(alert, animated: true, completion: nil)
                            }
                        }
                    }
                    else if let webAuthnAuthenticationCallaback = callback as? WebAuthnAuthenticationCallback {
                        webAuthnAuthenticationCallaback.delegate = self
                        
                        // Note that the `Node` parameter in `.authenticate()` is an optional parameter.
                        // If the node is provided, the SDK automatically sets the assertion to the designated HiddenValueCallback
                        webAuthnAuthenticationCallaback.authenticate(node: node) { (assertion) in
                            // Authentication is successful
                            // Submit the Node using Node.next()
                            node.next { (user: FRUser?, node, error) in
                                self.handleNode(user: user, node: node, error: error)
                            }
                        } onError: { (error) in
                            // An error occurred during the authentication process
                            // Submit the Node using Node.next()
                            let message: String
                            if let webAuthnError = error as? WebAuthnError, let platformError = webAuthnError.platformError() {
                                message = platformError.localizedDescription
                            } else if let webAuthnError = error as? WebAuthnError, let errorMessage = webAuthnError.message() {
                                message = errorMessage
                            } else {
                                message = "Something went wrong authenticating the device"
                            }
                            let alert = UIAlertController(title: "WebAuthnError", message: message, preferredStyle: .alert)
                            let okAction = UIAlertAction(title: "OK", style: .default, handler: { (action) in
                                node.next { (user: FRUser?, node, error) in
                                    self.handleNode(user: user, node: node, error: error)
                                }
                            })
                            alert.addAction(okAction)
                            DispatchQueue.main.async {
                                self.present(alert, animated: true, completion: nil)
                            }
                        }
                    } else if let hiddenValueCallback = callback as? HiddenValueCallback {
                        if hiddenValueCallback.id == "transactionID" {
                            hiddenValueCallback.setValue(self.transactionID)
                            node.next { (user: FRUser?, node, error) in
                                self.handleNode(user: user, node: node, error: error)
                            }
                        }
                    }
                }
                
                if let textfields = alert.textFields, textfields.count > 0 {
                    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                    let submitAction = UIAlertAction(title: "Next", style: .default) { (_) in
                        for (index, textField) in textfields.enumerated() {
                            if let thisCallback = node.callbacks[index] as? SingleValueCallback {
                                thisCallback.setValue(textField.text)
                            }
                        }
                        node.next { (user: FRUser?, node, error) in
                            self.handleNode(user: user, node: node, error: error)
                        }
                    }
                    
                    
                    alert.addAction(cancelAction)
                    alert.addAction(submitAction)
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }
        else {
            print ("Something went wrong: \(String(describing: error))")
        }
    }
    
    @IBAction func loginButtonPressed(_ sender: UIButton) {
        print("Login button is pressed")
        
        if self.transactionID != nil {
            self.startForgerockAuthentication()
        } else {
            self.startScanning()
        }
    }
    
    func startForgerockAuthentication() {
        FRUser.login {(user: FRUser?, node, error) in
            self.handleNode(user: user, node: node, error: error)
        }

        DispatchQueue.main.async {
            self.updateStatus()
        }
    }
    
    @IBAction func logoutButtonPressed(_ sender: UIButton) {
        print("Logout button is pressed")
        
        FRUser.currentUser
        
        FRUser.currentUser?.logout()
        
        DispatchQueue.main.async {
            self.updateStatus()
        }
    }
    
}

extension LoginViewController: PlatformAuthenticatorRegistrationDelegate {
    func excludeCredentialDescriptorConsent(consentCallback: @escaping WebAuthnUserConsentCallback) {
        let alert = UIAlertController(title: "Exclude Credentials", message: nil, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
            consentCallback(.reject)
        })
        let allowAction = UIAlertAction(title: "Allow", style: .default) { (_) in
            consentCallback(.allow)
        }
        alert.addAction(cancelAction)
        alert.addAction(allowAction)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func createNewCredentialConsent(keyName: String, rpName: String, rpId: String?, userName: String, userDisplayName: String, consentCallback: @escaping WebAuthnUserConsentCallback) {
        let alert = UIAlertController(title: "Create Credentials", message: "KeyName: \(keyName) | Relying Party Name: \(rpName) | User Name: \(userName)", preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
            consentCallback(.reject)
        })
        let allowAction = UIAlertAction(title: "Allow", style: .default) { (_) in
            consentCallback(.allow)
        }
        alert.addAction(cancelAction)
        alert.addAction(allowAction)
        
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
}

extension LoginViewController: PlatformAuthenticatorAuthenticationDelegate {
    func localKeyExistsAndPasskeysAreAvailable() {
        // Use this to offer upgade to Passkeys
    }
    
    func selectCredential(keyNames: [String], selectionCallback: @escaping WebAuthnCredentialsSelectionCallback) {
        let actionSheet = UIAlertController(title: "Select Credentials", message: nil, preferredStyle: .actionSheet)
        
        for keyName in keyNames {
            actionSheet.addAction(UIAlertAction(title: keyName, style: .default, handler: { (action) in
                selectionCallback(keyName)
            }))
        }
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) in
            selectionCallback(nil)
        }))
        
        if actionSheet.popoverPresentationController != nil {
            actionSheet.popoverPresentationController?.sourceView = self.view
            actionSheet.popoverPresentationController?.sourceRect = self.view.bounds
        }
        
        DispatchQueue.main.async {
            self.present(actionSheet, animated: true, completion: nil)
        }
    }
}

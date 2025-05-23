package com.example.samplefrapp;

import android.os.Bundle;
import android.widget.Button;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.app.AppCompatDelegate;

import com.regula.documentreader.api.DocumentReader;
import com.regula.documentreader.api.completions.IDocumentReaderInitCompletion;
import com.regula.documentreader.api.completions.rfid.IRfidReaderCompletion;
import com.regula.documentreader.api.config.ScannerConfig;
import com.regula.documentreader.api.enums.DocReaderAction;
import com.regula.documentreader.api.enums.Scenario;
import com.regula.documentreader.api.errors.DocumentReaderException;
import com.regula.documentreader.api.params.BackendProcessingConfig;
import com.regula.documentreader.api.params.DocReaderConfig;
import com.regula.documentreader.api.results.DocumentReaderResults;

import org.forgerock.android.auth.FRAuth;
import org.forgerock.android.auth.FRSession;
import org.forgerock.android.auth.FRUser;
import org.forgerock.android.auth.Logger;
import org.forgerock.android.auth.Node;
import org.forgerock.android.auth.NodeListener;
import org.forgerock.android.auth.callback.Callback;
import org.forgerock.android.auth.callback.HiddenValueCallback;
import org.forgerock.android.auth.callback.NameCallback;
import org.forgerock.android.auth.callback.TextOutputCallback;


public class MainActivity extends AppCompatActivity implements NodeListener<FRSession> {

    Button authnButton, logoutButton;
    TextView status;

    private String transactionID = "";

    protected void onCreate(@Nullable Bundle savedInstanceState) {
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_NO);

        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        authnButton = findViewById(R.id.authenticateButton);
        logoutButton = findViewById(R.id.logoutButton);
        status = findViewById(R.id.statusText);

        Logger.set(Logger.Level.DEBUG);
        FRAuth.start(this);
        initializationReader();

        updateStatus();

        authnButton.setOnClickListener(view -> {

            if (transactionID.isEmpty()) {
                startScanning();
            } else {
                startForgerockAuthentication();
            }
        });

        logoutButton.setOnClickListener(view -> {
            Logger.debug(TAG, "Logout button is pressed");
            try {
                FRUser.getCurrentUser().logout();
            } catch (Exception e) {
                Logger.error(TAG, e.getMessage(), e);
            }
            updateStatus();
        });
    }

    private void startForgerockAuthentication() {
        Logger.debug(TAG, "authN button is pressed");

        FRSession.authenticate(getApplicationContext(), "Regula-Demo", new NodeListener<FRSession>() {
            @Override
            public void onCallbackReceived(@NonNull Node node) {
                Logger.warn(TAG, "callback received in flow");
                MainActivity.this.onCallbackReceived(node);
            }

            @Override
            public void onSuccess(FRSession frSession) {
                Logger.warn(TAG, "onSuccess in flow");
                updateStatus();
            }

            @Override
            public void onException(@NonNull Exception e) {
                Logger.error(TAG, "Exception: " + e.getMessage());
            }
        });
    }

    @Override
    public void onCallbackReceived(@NonNull Node node) {
        runOnUiThread(() -> {

            Callback callback = node.getCallbacks().get(0);

            if (callback instanceof NameCallback) {
                NameOnlyDialogFragment fragment = NameOnlyDialogFragment.newInstance(node);
                fragment.show(getSupportFragmentManager(), NameOnlyDialogFragment.class.getName());
            } else if (callback instanceof HiddenValueCallback) {
                // Regula SDK gets transaction ID...
                // Set transactionID value in callback
                ((HiddenValueCallback) callback).setValue(transactionID);
                node.next(MainActivity.this, MainActivity.this);

            } else if (callback instanceof TextOutputCallback) {
                status.setText(((TextOutputCallback) callback).getMessage());
            }

        });

    }

    @Override
    public void onSuccess(FRSession frSession) {
        Logger.debug(TAG, "onSuccess in MainActivity");
        updateStatus();
    }

    @Override
    public void onException(@NonNull Exception e) {
        Logger.error(TAG, "Exception: " + e.getMessage());
    }

    private void updateStatus() {
        runOnUiThread(() -> {
            if (FRUser.getCurrentUser() == null) {
                status.setText("Not authenticated");
                authnButton.setEnabled(true);
                logoutButton.setEnabled(false);
            } else {
                status.setText("Authenticated");
                authnButton.setEnabled(false);
                logoutButton.setEnabled(true);
            }
        });
    }

    private void initializationReader() {
        byte[] license = LicenseUtil.getLicense( this);
        DocReaderConfig config = new DocReaderConfig(license);
        DocumentReader.Instance().initializeReader(this, config, new IDocumentReaderInitCompletion() {
            @Override
            public void onInitCompleted(boolean success, @Nullable DocumentReaderException e) {
                if (success) {
                    Logger.debug(TAG, "DocumentReader SDK initialized successfully");
                } else {
                    Logger.error(TAG, "DocumentReader SDK error: " + e.getMessage());
                }
            }
        });
    }

    private void startScanning() {
        ScannerConfig config = new ScannerConfig.Builder(Scenario.SCENARIO_FULL_PROCESS).build();

        // Setup backend processing
        BackendProcessingConfig backendProcessingConfig = new BackendProcessingConfig("https://dev-idv.regulaforensics.com/backdoor/drapi");
        backendProcessingConfig.setRfidServerSideChipVerification(false);
        DocumentReader.Instance().processParams().backendProcessingConfig = backendProcessingConfig;

        DocumentReader.Instance().showScanner(this, config, (action, documentReaderResults, e) -> {
            if (action == DocReaderAction.COMPLETE) {
                startRFIDReading();
            }
        });
    }

    private void startRFIDReading() {
        DocumentReader.Instance().startRFIDReader(this, new IRfidReaderCompletion() {
            @Override
            public void onCompleted(int action, @Nullable DocumentReaderResults documentReaderResults, @Nullable DocumentReaderException e) {
                if (action == DocReaderAction.COMPLETE) {
                    finalizeDocReader(documentReaderResults);
                }
            }
        });
    }

    private void finalizeDocReader(DocumentReaderResults results) {
        DocumentReader.Instance().finalizePackage((action, transactionInfo, e) -> {
            if (e != null) {
                Logger.error(TAG, "Exception: " + e.getMessage());
            } else {
                if (action == DocReaderAction.COMPLETE && transactionInfo != null) {
                    transactionID = transactionInfo.transactionId;
                    startForgerockAuthentication();
                }
            }
        });
    }
}

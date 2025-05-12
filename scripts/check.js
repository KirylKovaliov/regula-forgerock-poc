var PROCESS_BODY = JSON.stringify({
    processParam: { scenario: "FullProcess" }
});


var fr = JavaImporter(
    org.forgerock.util.Options,
    org.forgerock.http.protocol.Request,
    org.forgerock.http.protocol.Response,
    org.forgerock.openam.auth.node.api.NodeProcessException
);

logger.error("Shared State: " + sharedState);

/* ------------------------------------------------------------------
 * 1. Resolve configurable values from shared state or fall back.
 * ------------------------------------------------------------------ */
var DEFAULT_BASE_URL   = "https://dev-idv.regulaforensics.com/backdoor/drapi";
var DEFAULT_TXN_ID     = "c4d88caf-077e-49a7-a2d1-aaf2dc07e460";

var baseUrl       = ("" + sharedState.get("regulaBaseUrl"))      || DEFAULT_BASE_URL;
var transactionId = ("" + sharedState.get("transactionID"))      || DEFAULT_TXN_ID;

if (baseUrl == "null") {
  baseUrl = DEFAULT_BASE_URL;
}

if (transactionId == "null") {
  transactionId = DEFAULT_TXN_ID;
}


logger.error("Using Regula URL: "        + baseUrl);
logger.error("Using Transaction ID: "    + transactionId);


/* ------------------------------------------------------------------
 * 2. Process the document.
 * ------------------------------------------------------------------ */
try {
    var postUrl  = baseUrl + "/api/v2/transaction/" + transactionId + "/process";
    logger.error("POST → " + postUrl);

    var postReq  = new org.forgerock.http.protocol.Request();
    postReq.setUri(postUrl);
    postReq.setMethod("POST");
    postReq.getHeaders().put("Content-Type", "application/json");
    postReq.getEntity().setString(PROCESS_BODY);

    var postResp = httpClient.send(postReq).get();
    logger.error("POST status: " + postResp.getStatus().getCode());

    if (postResp.getStatus().getCode() >= 300) {
        logger.error("Process call failed, aborting.");
        outcome = "false";
    }
} catch (e) {
    logger.error("Exception during POST: " + e);
    outcome = "false";
}


/* ------------------------------------------------------------------
 * 3. Retrieve results with GET and validate overallStatus.
 * ------------------------------------------------------------------ */
try {
    var getUrl  = baseUrl + "/api/v2/transaction/" + transactionId + "/results?withImages=true";
    logger.error("GET  → " + getUrl);

    var getReq  = new org.forgerock.http.protocol.Request();
    getReq.setUri(getUrl);
    getReq.setMethod("GET");

    var getResp = httpClient.send(getReq).get();
    logger.error("GET status: " + getResp.getStatus().getCode());

    if (getResp.getStatus().getCode() !== 200) {
        logger.error("Results call failed, aborting.");
        outcome = "false";
        sharedState.put("regulaError", "Results call failed with status " + getResp.getStatus().getCode());
    }

    var respBody     = JSON.parse(getResp.getEntity().getString());
  	var containerList  = (((respBody || {}).ContainerList || {}).List) || [];
    var statusFound    = false;
    var statusIsOk     = false;

    for (var i = 0; i < containerList.length; i++) {
    	var cont = containerList[i];
        if (cont.Status) {
            statusFound = true;
            var overall = cont.Status.overallStatus;
            logger.error("Found Status.overallStatus=" + overall + " at List[" + i + "]");
            statusIsOk = (overall === 1);
            break;
        }
    }

  	if (!statusFound) {
        logger.error("No container with Status field found – failing.");
        sharedState.put("regulaError", "No Status container present");
        outcome = "false";
    } else if (!statusIsOk) {
        logger.error("overallStatus is not 1 – failing.");
        sharedState.put("regulaError", "overallStatus != 1");
        outcome = "false";
    } else {
        sharedState.put("regulaResult", respBody);
        outcome = "true";
    }

} catch (e) {
    logger.error("Exception during GET: " + e);
    outcome = "false";
}

outcome;
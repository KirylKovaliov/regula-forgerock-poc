try {
    if (callbacks.isEmpty()) {
        callbacksBuilder.hiddenValueCallback("transactionID", "false");
    } else {
        //Browser language can be used to localize custom callback messages
      	var transactionID = callbacks.getHiddenValueCallbacks().get("transactionID");
      	logger.error("transactionID v3: " + transactionID);
        nodeState.putShared("transactionID", transactionID);
    	action.goTo("true");
    }
    action.goTo("true");

} catch (error) {
    action.goTo("false");
    logger.error("Error getting transactionID: " + error.toString());
}
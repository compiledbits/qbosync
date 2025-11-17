@RestResource(urlMapping='/qbosync/webhook/qbo')
global without sharing class QBOWebhookHandler {
  private static String INTUIT_SIGNATURE_HEADER;
  private static String INTUIT_VERIFIER_TOKEN;
  private static String INTUIT_HMAC_ALGORITHM;

  /**
   * https://blogs.intuit.com/2025/10/14/introducing-enhanced-webhooks-monitoring
   * retries will happen at the following intervals: 0s, 10s, 20s, 30s, 5m, 20m, 2h, 4h, 6h and then on stays at 6 hour intervals.
   * note: that you may not receive subsequent events from our system until you correctly acknowledge the first event.
   *
   * https://developer.intuit.com/app/developer/qbo/docs/develop/webhooks
   * note: the retry policy frequency here ^ currently conflicts with the link above. i'm assuming this is the older version.
   * the retry service is only triggered for the following status codes: 500, 502, 503, 504, 408
   */
  private static final Integer RESPONSE_STATUS_CODE_SUCCESS = 200;
  private static final Integer RESPONSE_STATUS_CODE_ERROR_WITH_RETRY = 500;
  private static final Integer RESPONSE_STATUS_CODE_ERROR_NO_RETRY = 400;

  /**
   * online docs say this header should be `intuit_tid`
   * https://developer.intuit.com/app/developer/qbo/docs/learn/rest-api-features
   * but while testing i'm seeing `intuit-t-id`
   * so checking for both
   */
  @TestVisible
  private static final String INTUIT_TRACE_ID_HEADER_1 = 'intuit-t-id';
  @TestVisible
  private static final String INTUIT_TRACE_ID_HEADER_2 = 'intuit_tid';

  @HttpPost
  global static void doPost() {
    try {
      RestRequest request = RestContext.request;
      printRequestHeaders(request);

      if (!config()) {
        System.debug(LoggingLevel.ERROR, 'Invalid configuration. Returning a NON-retryable response.');
        RestContext.response.statusCode = RESPONSE_STATUS_CODE_ERROR_NO_RETRY;
        return;
      }

      System.debug('request body: ' + request.requestBody.toString());
      Boolean validHMAC = verifyHmac(request, INTUIT_VERIFIER_TOKEN);
      System.debug('valid HMAC: ' + validHMAC);

      String intuitTraceId = request.headers.get(INTUIT_TRACE_ID_HEADER_1) != null
        ? request.headers.get(INTUIT_TRACE_ID_HEADER_1)
        : request.headers.get(INTUIT_TRACE_ID_HEADER_2);

      if (validHMAC) {
        List<qbosync__QBO_Event__e> eventsToCreate = new List<qbosync__QBO_Event__e>();

        for (QBOEvent event : QBOEvent.parse(request.requestBody.toString())) {
          System.debug(event);
          eventsToCreate.add(
            new qbosync__QBO_Event__e(
              qbosync__id__c = event.Id,
              qbosync__type__c = event.type,
              qbosync__intuitaccountid__c = event.intuitaccountid,
              qbosync__intuitentityid__c = event.intuitentityid,
              qbosync__time__c = event.time_Z,
              qbosync__intuit_trace_id__c = intuitTraceId
            )
          );
        }

        System.debug(eventsToCreate);
        Boolean successful = true; // assume success unless an error is detected
        if (!eventsToCreate.isEmpty()) {
          successful = processSaveResult(EventBus.publish(eventsToCreate));
        }
        System.debug(successful);

        /**
         * WARNING:
         * `Boolean successful` is false if *any* event in the batch fails to publish.
         * This means partial success is possible, but returning HTTP 500 will cause
         * Intuit to retry the entire batch, potentially creating duplicates.
         *
         * This edge case is acceptable for now. If retries or duplicates become a
         * problem, revisit the event ingestion and publishing strategy.
         */
        RestContext.response.statusCode = successful
          ? RESPONSE_STATUS_CODE_SUCCESS
          : RESPONSE_STATUS_CODE_ERROR_WITH_RETRY;
      } else {
        System.debug(LoggingLevel.ERROR, 'Invalid HMAC. Returning a NON-retryable response.');
        RestContext.response.statusCode = RESPONSE_STATUS_CODE_ERROR_NO_RETRY;
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Unknown error. Returning a retryable response.\n' + e);
      RestContext.response.statusCode = RESPONSE_STATUS_CODE_ERROR_WITH_RETRY;
    }
  }

  /**
   * verifies the intuit webhook signature using apex crypto class
   */
  @TestVisible
  private static Boolean verifyHmac(RestRequest request, String verifier) {
    if (request == null || String.isBlank(verifier)) {
      return false;
    }

    String signature = request.headers.get(INTUIT_SIGNATURE_HEADER);
    if (String.isBlank(signature)) {
      return false;
    }

    return Crypto.verifyHmac(
      INTUIT_HMAC_ALGORITHM,
      request.requestBody,
      Blob.valueOf(verifier),
      EncodingUtil.base64Decode(signature)
    );
  }

  /**
   * set private static configuration variables
   *
   * @return TRUE if there are no issues, else FALSE
   */
  private static Boolean config() {
    List<qbosync__QBO_Webhook_Config__c> configs = [
      SELECT
        Id,
        Name,
        qbosync__Intuit_HMAC_Algorithm__c,
        qbosync__Intuit_Signature_Header__c,
        qbosync__Intuit_Verifier_Token__c
      FROM qbosync__QBO_Webhook_Config__c
      WHERE Name = 'Default'
    ];
    if (configs.size() != 1) {
      System.debug(
        LoggingLevel.ERROR,
        'Expected 1 QBO_Webhook_Config__c record with Name = \'Default\', but found: ' + configs.size()
      );
      return false;
    }
    qbosync__QBO_Webhook_Config__c config = configs[0];
    System.debug('config: ' + config);
    INTUIT_SIGNATURE_HEADER = config.qbosync__Intuit_Signature_Header__c;
    INTUIT_VERIFIER_TOKEN = config.qbosync__Intuit_Verifier_Token__c;
    INTUIT_HMAC_ALGORITHM = config.qbosync__Intuit_HMAC_Algorithm__c;

    return true;
  }

  /**
   * print the results of each: `Database.SaveResult`
   *
   * note: `Database.SaveResult` also contains an `Id` system field which is NOT included in the event message delivered to subscribers.
   * it isn’t used to identify an event message, and isn’t always unique.
   * the event's `UUID` will be returned `Database.Error.getMessage()` (even on a successful publish)
   *
   * @return FALSE if ANY SaveResult in the list was not successful
   */
  private static Boolean processSaveResult(List<Database.SaveResult> saveResults) {
    Boolean successful = true;

    for (Database.SaveResult sr : saveResults) {
      System.debug(sr);

      if (sr.isSuccess()) {
        System.debug('successfully published event');
        for (Database.Error err : sr.getErrors()) {
          System.debug('event status: ' + err.getStatusCode() + ', event UUID: ' + err.getMessage());
        }
      } else {
        successful = false;
        for (Database.Error err : sr.getErrors()) {
          System.debug(LoggingLevel.Error, 'Error returned: ' + err.getStatusCode() + ' - ' + err.getMessage());
        }
      }
    }

    System.debug(successful);
    return successful;
  }

  /**
   * print all incoming request header to the debug logs
   */
  private static void printRequestHeaders(RestRequest request) {
    System.debug('incoming HTTP request headers...');
    for (String key : request.headers.keySet()) {
      System.debug(key + ' = ' + request.headers.get(key));
    }
  }
}
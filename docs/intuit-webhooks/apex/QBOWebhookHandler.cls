/**
 * The retry service is only triggered for the following status codes: 500, 502, 503, 504, 408
 */
@RestResource(urlMapping='/qbosync/webhook/qbo')
global without sharing class QBOWebhookHandler {
  private static String INTUIT_SIGNATURE_HEADER;
  private static String INTUIT_VERIFIER_TOKEN;
  private static String INTUIT_HMAC_ALGORITHM;
  /**
   * online docs say this header should be `intuit_tid`
   * https://developer.intuit.com/app/developer/qbo/docs/learn/rest-api-features
   * but while testing i'm seeing `intuit-t-id`
   * so checking for both
   */
  private static final String INTUIT_TRACE_ID_HEADER_1 = 'intuit-t-id';
  private static final String INTUIT_TRACE_ID_HEADER_2 = 'intuit_tid';
  private static final String INTUIT_CREATED_TIME_HEADER = 'intuit-created-time';
  private static final String INTUIT_NOTIFICATION_SCHEMA_VERSION_HEADER = 'intuit-notification-schema-version';

  @HttpPost
  global static void doPost() {
    try {
      RestRequest request = RestContext.request;

      if (!config()) {
        RestContext.response.statusCode = 503; // intuit will re-try
        return;
      }

      System.debug(request.requestBody.toString());
      Boolean validHMAC = verifyHmac(request, INTUIT_VERIFIER_TOKEN);
      System.debug('valid HMAC: ' + validHMAC);

      String intuitTraceId = request.headers.get(INTUIT_TRACE_ID_HEADER_1) != null
        ? request.headers.get(INTUIT_TRACE_ID_HEADER_1)
        : request.headers.get(INTUIT_TRACE_ID_HEADER_2);
      String eventCreatedTime = request.headers.get(INTUIT_CREATED_TIME_HEADER);
      String notificationSchemaVersion = request.headers.get(INTUIT_NOTIFICATION_SCHEMA_VERSION_HEADER);

      if (validHMAC) {
        List<qbosync__QBO_Event_Notification__c> eventsToCreate = new List<qbosync__QBO_Event_Notification__c>();
        QBOEventNotification events = QBOEventNotification.parse(request.requestBody.toString());
        for (QBOEventNotification.EventNotifications realm : events.eventNotifications) {
          for (QBOEventNotification.Entities entity : realm.dataChangeEvent.entities) {
            System.debug(entity);

            qbosync__QBO_Event_Notification__c newEvent = new qbosync__QBO_Event_Notification__c(
              qbosync__Entity__c = entity.name,
              qbosync__Entity_Id__c = entity.id,
              qbosync__Operation__c = entity.operation,
              qbosync__Last_Updated__c = entity.lastUpdated,
              qbosync__Deleted_Id__c = entity.deletedID,
              qbosync__Event_Created_Time__c = eventCreatedTime,
              qbosync__Intuit_Trace_ID__c = intuitTraceId,
              qbosync__Notification_Schema_Version__c = notificationSchemaVersion
            );
            eventsToCreate.add(newEvent);
          }
        }

        if (eventsToCreate.isEmpty()) {
          System.debug(LoggingLevel.WARN, 'no events detected in the request body');
        } else {
          insert eventsToCreate;
        }

        RestContext.response.statusCode = 200;
      } else {
        RestContext.response.statusCode = 401; // intuit will NOT re-try
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, e);
      RestContext.response.statusCode = 500; // intuit will re-try
    }
  }

  /**
   * verifies the intuit webhook signature using apex crypto class
   */
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
}
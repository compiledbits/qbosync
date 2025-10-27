@IsTest
public class QBOWebhookHandler_Tests {
  private static String verifierToken_valid = '00000000-1111-2222-3333-444444444444';
  private static String verifierToken_invalid = '00000000-1111-2222-3333-444444444445'; // last character changed from 4 > 5

  private static String intuitSignature_valid = 'o2a30yYzzAGbAQCLkbGl5kpB1xvxEkdta62J3wJQR5M=';
  private static String intuitSignature_invalid = 'o2a30yYzzAGbAQCLkbGl5kpB1xvxEkdta62J3wJQR5Z='; // last character changed from M > Z

  private static String realmId_valid = '123456789000';
  private static String realmId_invalid = '123456789001'; // last character changed from 0 > 1

  private static String lastUpdated_valid = '2021-07-20T00:00:00.000Z';
  private static String lastUpdated_invalid = '2021-07-20T00:00:00.001Z'; // 1 millisecond ahead

  @TestSetup
  public static void makeData() {
    insert new qbosync__QBO_Webhook_Config__c(
      Name = 'Default',
      qbosync__Intuit_HMAC_Algorithm__c = 'HmacSHA256',
      qbosync__Intuit_Signature_Header__c = 'intuit-signature',
      qbosync__Intuit_Verifier_Token__c = verifierToken_valid
    );
  }

  @IsTest
  public static void doPost_success_200() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    System.assertEquals(200, RestContext.response.statusCode, 'Expected 200 for valid intuit-signature');
  }

  @IsTest
  public static void doPost_invalidSignature_401_alteredRealmId() {
    RestRequest request = getRestRequest(realmId_invalid, lastUpdated_valid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    System.assertEquals(
      401,
      RestContext.response.statusCode,
      'Expected 401 for invalid intuit-signature (realmId in payload has been altered)'
    );
  }

  @IsTest
  public static void doPost_invalidSignature_401_alteredTimestamp() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_invalid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    System.assertEquals(
      401,
      RestContext.response.statusCode,
      'Expected 401 for invalid intuit-signature (lastUpdated timestamp in payload has been altered)'
    );
  }

  @IsTest
  public static void doPost_invalidSignature_401_alteredSignature() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_invalid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    System.assertEquals(
      401,
      RestContext.response.statusCode,
      'Expected 401 for invalid intuit-signature (the response header has been altered)'
    );
  }

  @IsTest
  public static void doPost_invalidSignature_401_wrongVerifierToken() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_invalid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    qbosync__QBO_Webhook_Config__c config = [SELECT Id FROM qbosync__QBO_Webhook_Config__c LIMIT 1];
    config.qbosync__Intuit_Verifier_Token__c = verifierToken_invalid;
    update config;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    System.assertEquals(401, RestContext.response.statusCode, 'Expected 401 for invalid Intuit Verifier Token');
  }

  @IsTest
  public static void doPost_configMissing_503_noRecords() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    qbosync__QBO_Webhook_Config__c config = [SELECT Id FROM qbosync__QBO_Webhook_Config__c LIMIT 1];
    delete config;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    System.assertEquals(503, RestContext.response.statusCode, 'Expected 503 when config record is missing');
  }

  @IsTest
  public static void doPost_configMissing_503_multipleRecords() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    insert new qbosync__QBO_Webhook_Config__c(
      Name = 'Default',
      qbosync__Intuit_HMAC_Algorithm__c = 'HmacSHA256',
      qbosync__Intuit_Signature_Header__c = 'intuit-signature',
      qbosync__Intuit_Verifier_Token__c = 'test-duplicate'
    );

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    System.assertEquals(
      503,
      RestContext.response.statusCode,
      'Expected 503 when multiple Default config records exist'
    );
  }

  /**
   * generate a RestRequest
   *
   * @param realmId - injected into the response body
   * @param lastUpdated - injected into the response body
   * @param intuitSignature - value used for response header `intuit-signature`
   * @return RestRequest
   */
  private static RestRequest getRestRequest(String realmId, String lastUpdated, String intuitSignature) {
    String body =
      '{"eventNotifications":[{"realmId":"' +
      realmId +
      '","dataChangeEvent":{"entities":[{"id":"1","operation":"Update","name":"Customer","lastUpdated":"' +
      lastUpdated +
      '"}]}}]}';

    RestRequest request = new RestRequest();
    request.requestBody = Blob.valueOf(body);
    request.httpMethod = 'POST';
    request.remoteAddress = '44.233.250.12';
    request.requestURI = '/qbosync/webhook/qbo';
    request.resourcePath = '/services/apexrest/qbosync/webhook/qbo';
    request.addHeader('intuit-signature', intuitSignature);
    request.addHeader('Content-Type', 'application/json; charset=UTF-8');
    request.addHeader('Accept', 'application/json');

    return request;
  }
}
@IsTest
public class QBOWebhookHandler_Tests {
  private static final String verifierToken_valid = '00000000-1111-2222-3333-444444444444';
  private static final String verifierToken_invalid = '00000000-1111-2222-3333-444444444445'; // last character changed from 4 > 5

  private static final String intuitSignature_valid = 'MKqfBP+GjZLtr5RDa0MHc51dkKky1tGnL7hnEAfA8yA=';
  private static final String intuitSignature_invalid = 'MKqfBP+GjZLtr5RDa0MHc51dkKky1tGnL7hnEAfA8yZ='; // last character changed from A > Z

  private static final String realmId_valid = '123456789000';
  private static final String realmId_invalid = '123456789001'; // last character changed from 0 > 1

  private static final String lastUpdated_valid = '2021-07-20T00:00:00.000Z';
  private static final String lastUpdated_invalid = '2021-07-20T00:00:00.001Z'; // 1 millisecond ahead

  private static final String INTUIT_HMAC_ALGORITHM = 'HmacSHA256';
  private static final String INTUIT_SIGNATURE_HEADER = 'intuit-signature';
  private static final String QBO_WEBHOOK_CONFIG_DEFAULT_NAME = 'Default';

  @TestSetup
  public static void makeData() {
    insert new qbosync__QBO_Webhook_Config__c(
      Name = QBO_WEBHOOK_CONFIG_DEFAULT_NAME,
      qbosync__Intuit_HMAC_Algorithm__c = INTUIT_HMAC_ALGORITHM,
      qbosync__Intuit_Signature_Header__c = INTUIT_SIGNATURE_HEADER,
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

    Assert.areEqual(200, RestContext.response.statusCode, 'Expected 200 success');
  }

  @IsTest
  public static void doPost_partial_success_500() {
    // created valid request (this is the same request that was just validated with the test above)
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_valid);

    // then re-construct the request body to be *invalid*
    // qbosync__QBO_Event__e.qbosync__intuitaccountid__c is required
    // so blanking out intuitaccountid in the first event to cause an error publishing 1 of the 2 events
    String regExp = '(?<=intuitaccountid": ")[A-Za-z0-9]+'; // using a regex lookbehind assertion: (?<=pattern)
    String body = request.requestBody.toString().replaceFirst(regExp, '');

    // re-generate a *valid* MAC/signature for the *invalid* request body
    Blob intuitSignature = crypto.generateMac(
      INTUIT_HMAC_ALGORITHM,
      Blob.valueOf(body),
      Blob.valueOf(verifierToken_valid)
    );

    // put it all back together
    request.requestBody = Blob.valueOf(body);
    request.addHeader(INTUIT_SIGNATURE_HEADER, EncodingUtil.base64Encode(intuitSignature));
    RestContext.request = request;
    RestContext.response = new RestResponse();

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    Assert.areEqual(
      500,
      RestContext.response.statusCode,
      'Expected 500 due to partial success (one event missing intuitaccountid)'
    );
  }

  @IsTest
  public static void doPost_invalidSignature_400_alteredRealmId() {
    RestRequest request = getRestRequest(realmId_invalid, lastUpdated_valid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    Assert.areEqual(
      400,
      RestContext.response.statusCode,
      'Expected 400 due to invalid intuit-signature (realmId in payload has been altered)'
    );
  }

  @IsTest
  public static void doPost_invalidSignature_400_alteredTimestamp() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_invalid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    Assert.areEqual(
      400,
      RestContext.response.statusCode,
      'Expected 400 due to invalid intuit-signature (lastUpdated timestamp in payload has been altered)'
    );
  }

  @IsTest
  public static void doPost_invalidSignature_400_alteredSignature() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_invalid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    Assert.areEqual(
      400,
      RestContext.response.statusCode,
      'Expected 400 due to invalid intuit-signature (the response header has been altered)'
    );
  }

  @IsTest
  public static void doPost_invalidSignature_400_wrongVerifierToken() {
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

    Assert.areEqual(400, RestContext.response.statusCode, 'Expected 400 due to invalid Intuit Verifier Token');
  }

  @IsTest
  public static void doPost_configMissing_400_noRecords() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    qbosync__QBO_Webhook_Config__c config = [SELECT Id FROM qbosync__QBO_Webhook_Config__c LIMIT 1];
    delete config;

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    Assert.areEqual(400, RestContext.response.statusCode, 'Expected 400 when config record is missing');
  }

  /**
   * tests some miscellaneous edge cases
   */
  @IsTest
  public static void misc_tests() {
    // created valid request
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    // swap the 'intuit trace id' headers
    request.headers.remove(QBOWebhookHandler.INTUIT_TRACE_ID_HEADER_1);
    request.addHeader(QBOWebhookHandler.INTUIT_TRACE_ID_HEADER_2, 'does-not-matter');

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    // Assert.areEqual(expected, actual, msg);
    Assert.areEqual(200, RestContext.response.statusCode, 'Expected 200 success');

    Assert.isFalse(QBOWebhookHandler.verifyHmac(null, 'verifier'), 'Expected FALSE due to null RestRequest parameter');
    Assert.isFalse(QBOWebhookHandler.verifyHmac(request, ''), 'Expected FALSE due to blank verifier parameter');
    request.headers.remove(INTUIT_SIGNATURE_HEADER);
    Assert.isFalse(
      QBOWebhookHandler.verifyHmac(request, 'verifier'),
      'Expected FALSE due to missing intuit-signature request header'
    );
  }

  @IsTest
  public static void doPost_configMissing_400_multipleRecords() {
    RestRequest request = getRestRequest(realmId_valid, lastUpdated_valid, intuitSignature_valid);
    RestResponse response = new RestResponse();
    RestContext.request = request;
    RestContext.response = response;

    insert new qbosync__QBO_Webhook_Config__c(
      Name = QBO_WEBHOOK_CONFIG_DEFAULT_NAME,
      qbosync__Intuit_HMAC_Algorithm__c = INTUIT_HMAC_ALGORITHM,
      qbosync__Intuit_Signature_Header__c = INTUIT_SIGNATURE_HEADER,
      qbosync__Intuit_Verifier_Token__c = 'test-duplicate'
    );

    Test.startTest();
    QBOWebhookHandler.doPost();
    Test.stopTest();

    Assert.areEqual(400, RestContext.response.statusCode, 'Expected 400 when multiple Default config records exist');
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
      '[' +
      '  {' +
      '    \"specversion\": \"1.0\",' +
      '    \"id\": \"00000000-0000-0000-0000-000000000000\",' +
      '    \"source\": \"intuit.guid.example.abcdefghijklmnopqrstuvwxyz=\",' +
      '    \"type\": \"qbo.account.created.v1\",' +
      '    \"datacontenttype\": \"application/json\",' +
      '    \"time\": \"' +
      lastUpdated +
      '    \",' +
      '    \"intuitentityid\": \"1234\",' +
      '    \"intuitaccountid\": \"' +
      realmId +
      '    \",' +
      '    \"data\": {' +
      '      \"example\": \"value\"' +
      '    }' +
      '  },' +
      '  {' +
      '    \"specversion\": \"1.0\",' +
      '    \"id\": \"00000000-0000-0000-0000-111111111111\",' +
      '    \"source\": \"intuit.guid.example.abcdefghijklmnopqrstuvwxyz=\",' +
      '    \"type\": \"qbo.invoice.updated.v1\",' +
      '    \"datacontenttype\": \"application/json\",' +
      '    \"time\": \"' +
      lastUpdated +
      '    \",' +
      '    \"intuitentityid\": \"4321\",' +
      '    \"intuitaccountid\": \"' +
      realmId +
      '    \",' +
      '    \"data\": {' +
      '      \"example\": \"value\"' +
      '    }' +
      '  }' +
      ']';

    // Hard-coded request metadata used only to simulate a realistic inbound REST call.
    // These values are not referenced by test assertions and have no effect on test outcomes.
    // They exist solely to mirror the structure of a real QBO webhook request.
    RestRequest request = new RestRequest();
    request.requestBody = Blob.valueOf(body);
    request.httpMethod = 'POST';
    request.remoteAddress = '44.233.250.12';
    request.requestURI = '/qbosync/webhook/qbo';
    request.resourcePath = '/services/apexrest/qbosync/webhook/qbo';
    request.addHeader(INTUIT_SIGNATURE_HEADER, intuitSignature);
    request.addHeader('Content-Type', 'application/cloudevents-batch+json; charset=utf-8');
    request.addHeader('Accept', 'application/json');
    request.addHeader(QBOWebhookHandler.INTUIT_TRACE_ID_HEADER_1, '99999999-8888-7777-6666-555555555555');

    return request;
  }
}
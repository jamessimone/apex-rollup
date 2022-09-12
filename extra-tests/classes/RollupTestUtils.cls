@IsTest
public class RollupTestUtils {
  // from https://salesforce.stackexchange.com/questions/21137/creating-unit-tests-without-interacting-with-the-database-creating-fake-ids
  private static Integer startingNumber = 1;
  public static String createId(Schema.SObjectType sObjectType) {
    String result = String.valueOf(startingNumber++);
    return sObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - result.length()) + result;
  }

  public static List<Rollup.FlowInput> prepareFlowTest(List<SObject> records, String rollupContext, String rollupOperation) {
    Rollup.records = null; // just to ensure this is coming from the correct place

    Rollup.FlowInput flowInput = new Rollup.FlowInput();
    flowInput.recordsToRollup = records;
    flowInput.lookupFieldOnCalcItem = 'ParentId';
    flowInput.lookupFieldOnOpObject = 'Id';
    flowInput.rollupContext = rollupContext;
    flowInput.rollupFieldOnCalcItem = 'PreferenceRank';
    flowInput.rollupFieldOnOpObject = 'AnnualRevenue';
    flowInput.rollupSObjectName = 'Account';
    flowInput.rollupOperation = rollupOperation;
    flowInput.splitConcatDelimiterOnCalcItem = false;

    return new List<Rollup.FlowInput>{ flowInput };
  }

  public class DMLMock extends RollupSObjectUpdater {
    public List<SObject> Records = new List<SObject>();
    public override void doUpdate(List<SObject> recordsToUpdate) {
      RollupLogger.Instance.log('mock received the following for update:', recordsToUpdate, LoggingLevel.DEBUG);
      this.Records = recordsToUpdate;
    }
  }

  public static DMLMock loadAccountIdMock(List<SObject> records) {
    Account acc = [SELECT Id FROM Account];
    for (SObject record : records) {
      record.put('ParentId', acc.Id);
    }

    return loadMock(records);
  }

  public static DMLMock getTaskMock(List<SObject> records, Id cpaId) {
    for (SObject task : records) {
      task.put('WhatId', cpaId);
    }
    return loadMock(records);
  }

  public static DMLMock loadMock(List<SObject> records) {
    for (SObject record : records) {
      if (record.Id == null) {
        record.Id = createId(record.getSObjectType());
      }
    }
    Rollup.records = records;
    Rollup.shouldRun = true;
    DMLMock mock = new DMLMock();
    Rollup.DML = mock;

    return mock;
  }

  /**
   * Returns a record using dynamic SOQL to prevent CurrencyIsoCode from being strongly typed anywhere in the tests
   */
  public static SObject queryRecord(Id recordId) {
    return queryRecord(recordId, new List<Schema.SObjectField>());
  }

  public static SObject queryRecord(Id recordId, List<Schema.SObjectField> fieldNames) {
    return queryRecord(recordId, recordId.getSObjectType(), fieldNames);
  }

  public static SObject queryRecord(Schema.SObjectType fromObject, List<Schema.SObjectField> fieldNames) {
    return queryRecord(null, fromObject, fieldNames);
  }

  private static SObject queryRecord(Id recordId, Schema.SObjectType fromObject, List<Schema.SObjectField> fieldTokens) {
    String currencyIscoCodeFieldName = RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME;
    Set<String> fieldNames = new Set<String>();
    for (Schema.SObjectField fieldToken : fieldTokens) {
      fieldNames.add(fieldToken.getDescribe().getName());
    }

    if (fieldNames.contains('Name') == false) {
      fieldNames.add('Name');
    }
    if (UserInfo.isMultiCurrencyOrganization() && fromObject.getDescribe().fields.getMap().containsKey(currencyIscoCodeFieldName)) {
      fieldNames.add(currencyIscoCodeFieldName);
    }
    String whereClause = recordId == null ? '' : '\nWHERE Id = :recordId';
    String recordQuery = 'SELECT ' + String.join(new List<String>(fieldNames), ', ') + '\nFROM ' + fromObject + whereClause;
    return Database.query(recordQuery);
  }
}

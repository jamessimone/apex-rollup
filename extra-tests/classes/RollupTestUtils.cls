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

    return new List<Rollup.FlowInput>{ flowInput };
  }

  public class DMLMock extends RollupSObjectUpdater {
    public List<SObject> Records = new List<SObject>();
    public override void doUpdate(List<SObject> recordsToUpdate) {
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
    return queryRecord(recordId, new List<String>());
  }

  public static SObject queryRecord(Id recordId, List<String> fieldNames) {
    return queryRecord(recordId, null, fieldNames);
  }

  public static SObject queryrecord(String fromObject, List<String> fieldNames) {
    return queryRecord(null, fromObject, fieldNames);
  }

  private static SObject queryRecord(Id recordId, String fromObject, List<String> fieldNames) {
    SObjectType sObjectType = recordId != null ? recordId.getSObjectType() : ((SObject) Type.forName(fromObject).newInstance()).getSObjectType();
    String currencyIscoCodeFieldName = 'CurrencyIsoCode';
    if (fieldNames.contains('Id') == false) {
      fieldNames.add('Id');
    }
    if (fieldNames.contains('Name') == false) {
      fieldNames.add('Name');
    }
    if (UserInfo.isMultiCurrencyOrganization() && sObjectType.getDescribe().fields.getMap().containsKey(currencyIscoCodeFieldName)) {
      fieldNames.add(currencyIscoCodeFieldName);
    }
    String whereClause = recordId == null ? '' :  '\nWHERE Id = :recordId';
    String recordQuery = 'SELECT ' + String.join(fieldNames, ', ') + '\nFROM ' + sObjectType + whereClause;
    return Database.query(recordQuery);
  }
}

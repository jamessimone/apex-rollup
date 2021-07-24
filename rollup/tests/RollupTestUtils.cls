@isTest
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
}

@isTest
private class RollupRecursionItemTests {

  @isTest
  static void shouldReportFalseForNonRollupRecursionItemEquals() {
    RollupRecursionItem recursionItem = new RollupRecursionItem(null, new Rollup__mdt());

    System.assertEquals(false, recursionItem.equals(new Account()));
  }

  @isTest
  static void shouldReportTrueForEquivalentWrappedValues() {
    Account acc = new Account(Name = 'Hi', Id = RollupTestUtils.createId(Account.SObjectType));
    Rollup__mdt meta = new Rollup__mdt(RollupFieldOnCalcItem__c = 'Name', LookupFieldOnCalcItem__c = 'Id');

    RollupRecursionItem item = new RollupRecursionItem(acc, meta);
    RollupRecursionItem secondItem = new RollupRecursionItem(acc, meta);

    System.assertEquals(item, secondItem, 'Items with the same properties should match!');

    acc.Name = 'Hello';
    item = new RollupRecursionItem(acc, meta);

    System.assertNotEquals(item, secondItem);
  }

  @isTest
  static void shouldReportTrueForItemsWithSameNulledProps() {
    Rollup__mdt meta = new Rollup__mdt(RollupFieldOnCalcItem__c = 'Name', LookupFieldOnCalcItem__c = 'Id');

    RollupRecursionItem item = new RollupRecursionItem(new Account(), meta);
    RollupRecursionItem secondItem = new RollupRecursionItem(new Account(), meta);

    System.assertEquals(item, secondItem, 'Null properties should receive matching hash!');

    item = new RollupRecursionItem(new Account(Name = 'Some other string'), meta);
    System.assertNotEquals(item, secondItem, 'Once any prop is not null, equivalency should fail!');
  }

  @isTest
  static void shouldUseHashCodeWhenPerformingSetEquality() {
    Rollup__mdt meta = new Rollup__mdt(LookupFieldOnCalcItem__c = 'Id', RollupFieldOnCalcItem__c = 'Name');
    RollupRecursionItem item = new RollupRecursionItem(null, meta);
    RollupRecursionItem secondItem = new RollupRecursionItem(null, meta);

    Set<RollupRecursionItem> recursionItems = new Set<RollupRecursionItem>{ item };

    System.assertEquals(true, recursionItems.contains(secondItem));

    RollupRecursionItem nonMatchingItem = new RollupRecursionItem(new Account(Name = 'Test hashing'), meta);

    System.assertNotEquals(true, recursionItems.contains(nonMatchingItem));
  }

  @isTest
  static void shouldNotReportTrueIfSamePropsButDifferentCalcItemWhereFields() {
    System.assert(false, 'Fix me!');
  }
}

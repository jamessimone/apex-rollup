@IsTest
private class RollupRecursionItemTests {
  @IsTest
  static void shouldReportFalseForNonRollupRecursionItemEquals() {
    RollupRecursionItem recursionItem = new RollupRecursionItem(null, new Rollup__mdt(), 0);

    System.assertEquals(false, recursionItem.equals(new Account()));
  }

  @IsTest
  static void shouldReportTrueForEquivalentWrappedValues() {
    Account acc = new Account(Name = 'Hi', Id = RollupTestUtils.createId(Account.SObjectType));
    Rollup__mdt meta = new Rollup__mdt(RollupFieldOnCalcItem__c = 'Name', LookupFieldOnCalcItem__c = 'Id');

    RollupRecursionItem item = new RollupRecursionItem(acc, meta, 0);
    RollupRecursionItem secondItem = new RollupRecursionItem(acc, meta, 1);

    System.assertEquals(item, secondItem, 'Items with the same properties in different iterations should match!');

    acc.Name = 'Hello';
    item = new RollupRecursionItem(acc, meta, 0);

    System.assertNotEquals(item, secondItem);
  }

  @IsTest
  static void shouldReportTrueForItemsWithSameNulledProps() {
    Rollup__mdt meta = new Rollup__mdt(RollupFieldOnCalcItem__c = 'Name', LookupFieldOnCalcItem__c = 'Id');

    RollupRecursionItem item = new RollupRecursionItem(new Account(), meta, 0);
    RollupRecursionItem secondItem = new RollupRecursionItem(new Account(), meta, 1);

    System.assertEquals(item, secondItem, 'Null properties should receive matching hash!');

    item = new RollupRecursionItem(new Account(Name = 'Some other string'), meta, 0);
    System.assertNotEquals(item, secondItem, 'Once any prop is not null, equivalency should fail!');
  }

  @IsTest
  static void shouldUseHashCodeWhenPerformingSetEquality() {
    Rollup__mdt meta = new Rollup__mdt(LookupFieldOnCalcItem__c = 'Id', RollupFieldOnCalcItem__c = 'Name');
    RollupRecursionItem item = new RollupRecursionItem(null, meta, 0);
    RollupRecursionItem secondItem = new RollupRecursionItem(null, meta, 1);

    Set<RollupRecursionItem> recursionItems = new Set<RollupRecursionItem>{ item };

    System.assertEquals(true, recursionItems.contains(secondItem));

    RollupRecursionItem nonMatchingItem = new RollupRecursionItem(new Account(Name = 'Test hashing'), meta, 1);

    System.assertNotEquals(true, recursionItems.contains(nonMatchingItem));
  }

  @IsTest
  static void shouldNotReportTrueIfSamePropsButDifferentCalcItemWhereFields() {
    Account acc = new Account(Name = 'Hi', Id = RollupTestUtils.createId(Account.SObjectType), Description = 'Some description');
    Rollup__mdt meta = new Rollup__mdt(
      RollupFieldOnCalcItem__c = 'Name',
      LookupFieldOnCalcItem__c = 'Id',
      CalcItemWhereClause__c = 'Description != \'' + acc.Description + '\''
    );

    RollupRecursionItem item = new RollupRecursionItem(acc, meta, 0);

    Account clonedAccount = acc.clone(true, true);
    clonedAccount.Description = 'Some other description';
    RollupRecursionItem secondItem = new RollupRecursionItem(clonedAccount, meta, 0);

    System.assertNotEquals(item, secondItem);
  }
}

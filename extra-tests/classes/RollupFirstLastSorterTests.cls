@IsTest
private class RollupFirstLastSorterTests {
  @IsTest
  static void shouldOrderByTwoFieldsFirst() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount'),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    Opportunity expectedFirstItem = new Opportunity(Amount = null, CloseDate = severalDaysAgo);
    Opportunity expectedSecondItem = new Opportunity(Amount = 1, CloseDate = severalDaysAgo);
    List<Opportunity> oppsToSort = new List<Opportunity>{
      new Opportunity(Amount = 1, CloseDate = System.today()),
      // this record should essentially be thrown out of sorting since it "loses" on the first ordering,
      // which is on Amount
      new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1)),
      expectedSecondItem,
      expectedFirstItem
    };
    sorter.sort(oppsToSort);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
  }

  @IsTest
  static void shouldOrderByTwoFieldsLast() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.LAST,
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount'),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    Opportunity expectedFirstItem = new Opportunity(Amount = 6, CloseDate = severalDaysAgo);
    Opportunity expectedSecondItem = new Opportunity(Amount = 4, CloseDate = severalDaysAgo);
    List<Opportunity> oppsToSort = new List<Opportunity>{
      new Opportunity(Amount = 1, CloseDate = System.today()),
      new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1)),
      expectedSecondItem,
      expectedFirstItem
    };
    sorter.sort(oppsToSort);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
  }

  @IsTest
  static void shouldOrderByMultipleFields() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount'),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate'),
        new RollupOrderBy__mdt(Ranking__c = 2, FieldName__c = 'Name')
      }
    );

    Date today = System.today().addDays(-2);
    Opportunity expectedFirstItem = new Opportunity(Amount = 1, CloseDate = today, Name = 'b');
    Opportunity expectedThirdItem = new Opportunity(Amount = 2, CloseDate = today, Name = 'a');
    Opportunity expectedSecondItem = new Opportunity(Amount = 1, CloseDate = today, Name = 'c');
    Opportunity expectedFourthItem = new Opportunity(Amount = 2, CloseDate = today.addDays(1), Name = 'a');
    List<Opportunity> oppsToSort = new List<Opportunity>{ expectedSecondItem, expectedFourthItem, expectedThirdItem, expectedFirstItem };
    sorter.sort(oppsToSort);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
    System.assertEquals(expectedThirdItem, oppsToSort[2]);
    System.assertEquals(expectedFourthItem, oppsToSort[3]);
  }

  @IsTest
  static void shouldOrderNullsLast() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount', NullSortOrder__c = RollupMetaPicklists.NullSortOrder.NullsLast),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    Opportunity expectedFirstItem = new Opportunity(Amount = 1, CloseDate = System.today());
    Opportunity expectedSecondItem = new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1));
    List<Opportunity> oppsToSort = new List<Opportunity>{
      new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1)),
      expectedSecondItem,
      expectedFirstItem
    };
    sorter.sort(oppsToSort);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
  }

  @IsTest
  static void shouldOrderDescWhenStipulated() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount', SortOrder__c = RollupMetaPicklists.SortOrder.Descending),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate')
      }
    );

    Date today = System.today();
    // validates null sort order plays nice with this
    Opportunity expectedFirstItem = new Opportunity(Amount = null, CloseDate = today);
    Opportunity expectedSecondItem = new Opportunity(Amount = 5, CloseDate = today);
    Opportunity expectedThirdItem = new Opportunity(Amount = 1, CloseDate = today);

    List<Opportunity> oppsToSort = new List<Opportunity>{ expectedThirdItem, expectedFirstItem, expectedSecondItem };
    sorter.sort(oppsToSort);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
    System.assertEquals(expectedThirdItem, oppsToSort[2]);
  }

  @IsTest
  static void shouldProperlySortPicklists() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Industry') }
    );

    List<Schema.PicklistEntry> picklistEntries = Account.Industry.getDescribe().getPicklistValues();
    List<Account> accs = new List<Account>();

    for (Integer reverseIndex = picklistEntries.size() - 1; reverseIndex >= 0; reverseIndex--) {
      Schema.PicklistEntry entry = picklistEntries[reverseIndex];
      accs.add(new Account(Name = entry.getValue(), Industry = entry.getValue()));
    }

    sorter.sort(accs);

    for (Integer index = 0; index < accs.size(); index++) {
      System.assertEquals(picklistEntries[index].getValue(), accs[index].Industry, 'Account at index: ' + index + ' should have matched');
    }
  }

  @IsTest
  static void shouldSortParentFields() {
    Account acc = new Account(Name = 'Parent');
    insert acc;

    Opportunity opp = new Opportunity(Account = acc, Amount = 1);
    Opportunity second = new Opportunity(Account = acc, Amount = 2);

    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Account.Name'),
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount')
      }
    );

    List<Opportunity> opps = new List<Opportunity>{ second, opp };
    sorter.sort(opps);

    System.assertEquals(opp, opps[0]);
    System.assertEquals(second, opps[1]);
  }

  @IsTest
  static void shouldNotFailOnBlankFieldNames() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount'), new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = '') }
    );

    Opportunity expectedFirstItem = new Opportunity(Amount = null);
    Opportunity expectedSecondItem = new Opportunity(Amount = 1);
    List<Opportunity> oppsToSort = new List<Opportunity>{ new Opportunity(Amount = 1), new Opportunity(Amount = 3), expectedSecondItem, expectedFirstItem };
    sorter.sort(oppsToSort);

    System.assert(true, 'Should make it here');
  }
}

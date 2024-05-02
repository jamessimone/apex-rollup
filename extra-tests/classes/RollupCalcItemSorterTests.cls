@IsTest
private class RollupCalcItemSorterTests {
  @IsTest
  static void shouldOrderByTwoFields() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount'),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    Opportunity expectedFirstItem = new Opportunity(Amount = null, CloseDate = severalDaysAgo);
    Opportunity expectedSecondItem = new Opportunity(Amount = 1, CloseDate = severalDaysAgo);
    List<RollupCalculator.WinnowResult> oppsToSort = new List<RollupCalculator.WinnowResult>{
      new RollupCalculator.WinnowResult(new Opportunity(Amount = 1, CloseDate = System.today())),
      // this record should essentially be thrown out of sorting since it "loses" on the first ordering,
      // which is on Amount
      new RollupCalculator.WinnowResult(new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1))),
      new RollupCalculator.WinnowResult(expectedSecondItem),
      new RollupCalculator.WinnowResult(expectedFirstItem)
    };
    oppsToSort.sort(sorter);

    System.assertEquals(expectedFirstItem, oppsToSort[0].item);
    System.assertEquals(expectedSecondItem, oppsToSort[1].item);
  }

  @IsTest
  static void shouldOrderByMultipleFields() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
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
    List<RollupCalculator.WinnowResult> oppsToSort = new List<RollupCalculator.WinnowResult>{
      new RollupCalculator.WinnowResult(expectedSecondItem),
      new RollupCalculator.WinnowResult(expectedFourthItem),
      new RollupCalculator.WinnowResult(expectedThirdItem),
      new RollupCalculator.WinnowResult(expectedFirstItem)
    };
    oppsToSort.sort(sorter);

    System.assertEquals(expectedFirstItem, oppsToSort[0].item);
    System.assertEquals(expectedSecondItem, oppsToSort[1].item);
    System.assertEquals(expectedThirdItem, oppsToSort[2].item);
    System.assertEquals(expectedFourthItem, oppsToSort[3].item);
  }

  @IsTest
  static void shouldOrderNullsLast() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount', NullSortOrder__c = RollupMetaPicklists.NullSortOrder.NullsLast),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    Opportunity expectedFirstItem = new Opportunity(Amount = 1, CloseDate = System.today());
    Opportunity expectedSecondItem = new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1));
    List<RollupCalculator.WinnowResult> oppsToSort = new List<RollupCalculator.WinnowResult>{
      new RollupCalculator.WinnowResult(new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1))),
      new RollupCalculator.WinnowResult(expectedSecondItem),
      new RollupCalculator.WinnowResult(expectedFirstItem)
    };
    oppsToSort.sort(sorter);

    System.assertEquals(expectedFirstItem, oppsToSort[0].item);
    System.assertEquals(expectedSecondItem, oppsToSort[1].item);
  }

  @IsTest
  static void shouldOrderDescWhenStipulated() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
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

    List<RollupCalculator.WinnowResult> oppsToSort = new List<RollupCalculator.WinnowResult>{
      new RollupCalculator.WinnowResult(expectedThirdItem),
      new RollupCalculator.WinnowResult(expectedFirstItem),
      new RollupCalculator.WinnowResult(expectedSecondItem)
    };
    oppsToSort.sort(sorter);

    System.assertEquals(expectedFirstItem, oppsToSort[0].item);
    System.assertEquals(expectedSecondItem, oppsToSort[1].item);
    System.assertEquals(expectedThirdItem, oppsToSort[2].item);
  }

  @IsTest
  static void shouldProperlySortPicklists() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Industry') });

    List<Schema.PicklistEntry> picklistEntries = Account.Industry.getDescribe().getPicklistValues();
    List<RollupCalculator.WinnowResult> accs = new List<RollupCalculator.WinnowResult>();

    for (Integer reverseIndex = picklistEntries.size() - 1; reverseIndex >= 0; reverseIndex--) {
      Schema.PicklistEntry entry = picklistEntries[reverseIndex];
      accs.add(new RollupCalculator.WinnowResult(new Account(Name = entry.getValue(), Industry = entry.getValue())));
    }
    accs.sort(sorter);

    for (Integer index = 0; index < accs.size(); index++) {
      System.assertEquals(picklistEntries[index].getValue(), accs[index].item.get(Account.Industry), 'Account at index: ' + index + ' should have matched');
    }
  }

  @IsTest
  static void shouldSortParentFields() {
    Account acc = new Account(Name = 'Parent');
    insert acc;

    Opportunity opp = new Opportunity(Account = acc, Amount = 1);
    Opportunity second = new Opportunity(Account = acc, Amount = 2);

    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Account.Name'),
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount')
      }
    );

    List<RollupCalculator.WinnowResult> opps = new List<RollupCalculator.WinnowResult>{
      new RollupCalculator.WinnowResult(second),
      new RollupCalculator.WinnowResult(opp)
    };
    opps.sort(sorter);

    System.assertEquals(opp, opps[0].item);
    System.assertEquals(second, opps[1].item);
  }

  @IsTest
  static void shouldNotFailOnBlankFieldNames() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount'), new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = '') }
    );

    Opportunity expectedFirstItem = new Opportunity(Amount = null);
    Opportunity expectedSecondItem = new Opportunity(Amount = 1);
    List<RollupCalculator.WinnowResult> oppsToSort = new List<RollupCalculator.WinnowResult>{
      new RollupCalculator.WinnowResult(new Opportunity(Amount = 1)),
      new RollupCalculator.WinnowResult(new Opportunity(Amount = 3)),
      new RollupCalculator.WinnowResult(expectedSecondItem),
      new RollupCalculator.WinnowResult(expectedFirstItem)
    };
    oppsToSort.sort(sorter);

    System.assert(true, 'Should make it here');
  }

  @IsTest
  static void sortsFieldNames() {
    List<RollupCalculator.WinnowResult> itemsToSort = new List<RollupCalculator.WinnowResult>{
      new RollupCalculator.WinnowResult(new Opportunity(StageName = 'Two')),
      new RollupCalculator.WinnowResult(new Opportunity(StageName = 'Uno Reverse Card')),
      new RollupCalculator.WinnowResult(new Opportunity(StageName = 'Two')),
      new RollupCalculator.WinnowResult(new Opportunity()),
      new RollupCalculator.WinnowResult(new Opportunity(StageName = 'Z')),
      new RollupCalculator.WinnowResult(new Opportunity(StageName = 'One')),
      new RollupCalculator.WinnowResult(new Opportunity(StageName = 'One'))
    };

    itemsToSort.sort(new RollupCalcItemSorter(new List<String>{ Opportunity.Name.getDescribe().getName(), Opportunity.StageName.getDescribe().getName() }));

    System.assertEquals(null, itemsToSort.get(0).item.get(Opportunity.StageName));
    System.assertEquals('One', itemsToSort.get(1).item.get(Opportunity.StageName));
    System.assertEquals('One', itemsToSort.get(2).item.get(Opportunity.StageName));
    System.assertEquals('Two', itemsToSort.get(3).item.get(Opportunity.StageName));
    System.assertEquals('Two', itemsToSort.get(4).item.get(Opportunity.StageName));
    System.assertEquals('Uno Reverse Card', itemsToSort.get(5).item.get(Opportunity.StageName));
    System.assertEquals('Z', itemsToSort.get(6).item.get(Opportunity.StageName));
  }
}

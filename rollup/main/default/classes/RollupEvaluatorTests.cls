@isTest
private class RollupEvaluatorTests {
  @isTest
  static void shouldReturnEqualsCorrectlyForEqualsCriteria() {
    Opportunity nameEquals = new Opportunity(Name = 'RollupZ');
    Opportunity doesNotEqualName = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name = \'RollupZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'Name should match RollupZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'Name should not match RollupZ');
  }

  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEquals() {
    Opportunity nameEquals = new Opportunity(Name = 'RollupZ');
    Opportunity doesNotEqualName = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name != \'RollupZZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'RollupZ should match since it does not equal RollupZZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'RollupZZ should not match');
  }

  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEqualsAlternate() {
    Opportunity nameEquals = new Opportunity(Name = 'RollupZ');
    Opportunity doesNotEqualName = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name <> \'RollupZZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'RollupZ should match since it does not equal RollupZZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'RollupZZ should not match');
  }

  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldEqualsMultiple() {
    Opportunity rollupZ = new Opportunity(Name = 'RollupZ');
    Opportunity rollupZZ = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name IN (\'RollupZZ\', \'RollupZ\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, rollupZ.getSObjectType());

    System.assertEquals(true, eval.matches(rollupZ), 'Should match based on IN');
    System.assertEquals(true, eval.matches(rollupZZ), 'Should match based on IN');
  }

  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEqualsMultiple() {
    Opportunity rollupZ = new Opportunity(Name = 'RollupZ');
    Opportunity rollupZZ = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name NOT IN (\'RollupZZ\', \'RollupZ\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, rollupZ.getSObjectType());

    System.assertNotEquals(true, eval.matches(rollupZ), 'Should not match based on NOT IN');
    System.assertNotEquals(true, eval.matches(rollupZZ), 'Should not match based on NOT IN');
  }

  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForParentFields() {
    Account acc = new Account(Name = 'RollupEvaluatorTests');
    Opportunity oppOne = new Opportunity(Name = acc.Name, Account = acc);
    Opportunity oppTwo = new Opportunity(Name = 'RollupZ', Account = new Account(Name = 'Some other name'));
    String whereClause = 'Account.Name != ' + acc.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match since the name is different than the parent field name');
  }

  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForOrStatements() {
    Account acc = new Account(Name = 'RollupEvaluatorTests');
    Opportunity oppOne = new Opportunity(Name = acc.Name, Account = acc);
    Opportunity oppTwo = new Opportunity(Name = 'RollupZ', Account = acc);
    Opportunity oppThree = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Account.Name != \'' + acc.Name + '\' OR Name = \'' + oppTwo.Name + '\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match since the name exactly matches the OR clause');
    System.assertEquals(true, eval.matches(oppThree), 'Should match since the account name does not match');
  }

  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForLikeStatements() {
    Account acc = new Account(Name = 'RollupEvaluatorTest');
    Opportunity oppOne = new Opportunity(Name = 'RollupZZ', Account = acc);
    Opportunity oppTwo = new Opportunity(Name = 'RollupZ', Account = acc);

    String whereClause = 'Account.Name LIKE \'%Rollup%\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Should match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match based on parent field');
  }

  @isTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForNotLikeStatements() {
    Account acc = new Account(Name = 'RollupEvaluatorTest');
    Opportunity oppOne = new Opportunity(Name = 'RollupZZ', Account = acc);
    Opportunity oppTwo = new Opportunity(Name = 'RollupZ', Account = acc);

    String whereClause = 'Account.Name NOT LIKE \'%Rollup%\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match based on parent field');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Should not match based on parent field');
  }

  @isTest
  static void shouldFilerCalcItemsThatContainAndOrStringsThatAreNotFilterConditions() {
    Opportunity oppOne = new Opportunity(Name = 'A or B');
    Opportunity oppTwo = new Opportunity(Name = 'A and B');

    String whereClause = 'Name = \'A or B\''; // gasp

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Where clause should not have been split in the wrong place!');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Where clause should not have been split in the wrong place!');
  }

  @isTest
  static void shouldWorkForStringsWithSymbolsInThem() {
    Opportunity oppOne = new Opportunity(Name = '!()eeeek$$$-@');

    String whereClause = 'Name = \'!()eeeek$$$-@\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Where clause should not have been split in the wrong place!');
  }

  @isTest
  static void shouldWorkForGreaterThanConditions() {
    Opportunity oppOne = new Opportunity();
    Opportunity oppTwo = new Opportunity(Amount = 5);
    Opportunity oppThree = new Opportunity(Amount = 3.01);

    String whereClause = 'Amount > 4';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match due to not having amount!');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match since amount is greater than');
    System.assertNotEquals(true, eval.matches(oppThree), 'Should not match since amount is not greater than');

    eval = new RollupEvaluator.WhereFieldEvaluator('Amount >= 4.00', oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(new Opportunity(Amount = 4.00)), 'Should match since amount equals!');
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 5.00)), 'Should match since amount greater than!');
  }

  @isTest
  static void shouldWorkForLessThanConditions() {
    Opportunity oppOne = new Opportunity();
    Opportunity oppTwo = new Opportunity(Amount = 5);
    Opportunity oppThree = new Opportunity(Amount = 3.01);

    String whereClause = 'Amount < 4';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match due to not having amount');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Should not match since amount is greater than criteria');
    System.assertEquals(true, eval.matches(oppThree), 'Should match since amount is less than');

    eval = new RollupEvaluator.WhereFieldEvaluator('Amount <= 4.00', oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(new Opportunity(Amount = 4.00)), 'Should match since amount equals!');
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 3.00)), 'Should match since amount less than!');
  }

  @isTest
  static void shouldReturnCorrectlyForNestedConditionals() {
    Opportunity oppOne = new Opportunity(StageName = 'Not A Match');
    Opportunity oppTwo = new Opportunity(Amount = 5, StageName = 'Hi');
    Opportunity oppThree = new Opportunity(Amount = 3.01, StageName = 'Hello there');
    Opportunity oppFour = new Opportunity(StageName = 'Hi', Amount = 0);
    Opportunity oppFive = new Opportunity(Id = '0066g000000000000T', Amount = 3.99999);

    String whereClause =
      'Amount < 4 AND (StageName LIKE \'%Hello%\' OR StageName = \'Hi\' OR (Id IN (\'' +
      oppFive.Id +
      '\' AND Amount = ' +
      oppFive.Amount +
      ')))';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Name does not match!');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Amount does not match');
    System.assertEquals(true, eval.matches(oppThree), 'Amount and name roughly match!');
    System.assertEquals(true, eval.matches(oppFour), 'Amount and name match');
    System.assertEquals(true, eval.matches(oppFive), 'Id matches inner nested conditional!');
  }

  @isTest
  static void shouldReturnForMultipleOrConditionalsWithQueryKeywordsInString() {
    Opportunity oppOne = new Opportunity(ForecastCategoryName = 'Omitted');
    Opportunity oppTwo = new Opportunity(ForecastCategoryName = 'Pipeline'); // pipeline has "in" within it; this is a query keyword that should not get replaced
    Opportunity oppThree = new Opportunity(ForecastCategoryName = 'Best Case');
    Opportunity oppFour = new Opportunity(ForecastCategoryName = 'Commit');
    Opportunity oppFive = new Opportunity(Amount = 5, ForecastCategoryName = 'Closed');
    Formula.recalculateFormulas(new List<Opportunity>{ oppOne, oppTwo, oppThree, oppFour, oppFive });

    String whereClause = 'ForecastCategoryName = \'Omitted\' OR ForecastCategoryName = \'Best Case\' OR ForecastCategoryName = \'Pipeline\' OR Amount = 5';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(true, eval.matches(oppOne), 'ForecastCategoryName for opp one should match');
    System.assertEquals(true, eval.matches(oppTwo), 'ForecastCategoryName for opp two should match');
    System.assertEquals(true, eval.matches(oppThree), 'ForecastCategoryName for opp three should match');
    System.assertEquals(false, eval.matches(oppFour), 'ForecastCategoryName for opp four should not match');
    System.assertEquals(true, eval.matches(oppFive), 'Amount for opp five should match');
  }

  @isTest
  static void shouldReturnCorrectlyWhenQueryKeywordsWithSpacesArePartOfString() {
    // even worse than the above - imagine a Name field "This in That" returning false
    // because we've mistakenly transformed it into "This = that" 🤦‍♂️

    Opportunity nameShouldMatch = new Opportunity(Name = 'This in That');
    String whereClause = 'Name = \'This in That\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);
    System.assertEquals(true, eval.matches(nameShouldMatch), 'Name should match');
  }

  @isTest
  static void shouldReturnDualEvaluatorWhenCalcItemChangedFieldsAndWhereClauseFilledOut() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, StageName = 'Updated Name');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.StageName = 'Old Name';

    Opportunity secondOpp = new Opportunity(Id = '0066g000000000000Z', StageName = 'Same', Amount = 25);

    Rollup__mdt rollupMetadata = new Rollup__mdt(ChangedFieldsOnCalcItem__c = 'StageName', CalcItemWhereClause__c = 'Amount > 20');

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp, secondOpp.Id => secondOpp },
      Opportunity.SObjectType
    );
    System.assertEquals(true, eval.matches(opp), 'Should match since StageName has changed and amount > 20');
    System.assertNotEquals(true, eval.matches(secondOpp), 'Should not match, stage name unchanged even though amount > 20');
  }

  @isTest
  static void shouldReturnDualEvaluatorWhenCalcItemReparented() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', AccountId = '0016g000000000000X', Amount = 50);
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.AccountId = '0013g000000000000Z';

    Rollup__mdt rollupMetadata = new Rollup__mdt(CalcItemWhereClause__c = 'Amount > 20');

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(rollupMetadata, new Map<Id, SObject>{ oldOpp.Id => oldOpp }, Opportunity.SObjectType);
    System.assertEquals(true, eval.matches(opp), 'Should match since StageName has changed and amount > 20');
  }
}

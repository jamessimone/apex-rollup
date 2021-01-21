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
    String whereClause = 'Account.Name != \'' + acc.Name + '\' OR Name = \'' + oppTwo.Name + '\'' + ' AND Name != \'RollupZZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match since the name exactly matches the OR clause');
    System.assertNotEquals(true, eval.matches(oppThree), 'Should not match based on name field');
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

    Test.startTest();
    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Should match due to not having amount');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Should not match since amount is greater than criteria');
    System.assertEquals(true, eval.matches(oppThree), 'Should match since amount is less than');

    eval = new RollupEvaluator.WhereFieldEvaluator('Amount <= 4.00', oppOne.getSObjectType());
    Test.stopTest();

    System.assertEquals(true, eval.matches(new Opportunity(Amount = 4.00)), 'Should match since amount equals!');
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 3.00)), 'Should match since amount less than!');
  }


  // dual conditions (where and record changed), and the record changed tests, nested conditionals
}


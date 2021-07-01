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
  static void shouldFilterCalcItemsForNotEqualsNumbers() {
    Opportunity notZero = new Opportunity(Amount = 10);
    Opportunity zero = new Opportunity(Amount = 0);
    String whereClause = 'Amount != 0';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, zero.getSObjectType());

    System.assertEquals(true, eval.matches(notZero), String.valueOf(notZero.Amount) + ' should not = 0');
    System.assertNotEquals(true, eval.matches(zero), '0 should  be excluded since opp amount = ' + zero.Amount);
  }

  @isTest
  static void shouldNotFilterCalcItemsBasedOnWhereClauseWithInOrNotIn() {
    Account acc = new Account(Name = 'Something & Something Else');
    Account two = new Account(Name = 'Vertical/Backslash');
    Account doesNotMatch = new Account(Name = 'Something with in the string');
    Account three = new Account(Name = 'basic string');

    String whereClause = 'Name != \'Something with in the string\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, acc.getSObjectType());

    System.assertNotEquals(true, eval.matches(doesNotMatch), 'In should not be replaced');
    System.assertEquals(true, eval.matches(acc));
    System.assertEquals(true, eval.matches(two));
    System.assertEquals(true, eval.matches(three));

    whereClause = 'Name != \'Something with not in the string\'';
    eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, acc.getSObjectType());

    System.assertNotEquals(true, eval.matches(new Account(Name = 'Something with not in the string')));
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
  static void shouldFilterCalcItemsBasedOnWhereClauseForLists() {
    List<String> accIds = new List<String>{ '0016g0000000000001', '0016g0000000000002' };
    String whereClause = 'AccountId IN ' + JSON.serialize(accIds).replace('[', '(').replace(']', ')').replaceAll('"', '\'');

    Opportunity oppOne = new Opportunity(AccountId = accIds[0]);
    Opportunity oppTwo = new Opportunity(accountId = accIds[1]);
    Opportunity shouldNotMatch = new Opportunity(AccountId = '0016g0000000000003');

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());
    System.assertEquals(true, eval.matches(oppOne), 'first account Id is in list');
    System.assertEquals(true, eval.matches(oppTwo), 'second account Id is in list');
    System.assertNotEquals(true, eval.matches(shouldNotMatch), 'third account Id is not in list');
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
  static void shouldFilterCalcItemsThatContainAndOrStringsThatAreNotFilterConditions() {
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
  static void shouldWorkForParanthesisAtEndOfString() {
    Opportunity nameWithParanthesis = new Opportunity(Name = 'Realized Gain/(Loss)');

    String whereClause = 'Name = \'Realized Gain/(Loss)\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameWithParanthesis.getSObjectType());

    System.assertEquals(true, eval.matches(nameWithParanthesis), 'Where clause should not have been split in the wrong place!');
  }

  @isTest
  static void shouldWorkForGreaterThanNumbers() {
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
  static void shouldWorkForGreaterThanDates() {
    Opportunity oppOne = new Opportunity(CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(CloseDate = System.today().addDays(-2));

    String whereClause = 'CloseDate > ' + oppTwo.CloseDate;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo), 'Second close date should not match since it is not greater: ' + oppTwo.CloseDate);
  }

  @isTest
  static void shouldWorkForGreaterThanDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(2));

    String whereClause = 'ActivityDateTime > ' + evOne.ActivityDateTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(false, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @isTest
  static void shouldWorkForGreaterThanTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime > ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(false, eval.matches(cpa));
    System.assertEquals(true, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @isTest
  static void shouldWorkForGreaterThanOrEqualDates() {
    Opportunity oppOne = new Opportunity(CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(CloseDate = System.today().addDays(-2));

    String whereClause = 'CloseDate >= ' + oppTwo.CloseDate;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @isTest
  static void shouldWorkForGreaterThanOrEqualsTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime >= ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(true, eval.matches(cpa));
    System.assertEquals(true, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @isTest
  static void shouldWorkForGreaterThanOrEqualsDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime >= ' + evOne.ActivityDateTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(true, eval.matches(evOne));
    System.assertEquals(false, eval.matches(evTwo));
  }

  @isTest
  static void shouldWorkForGreaterThanStrings() {
    Opportunity oppOne = new Opportunity(Name = 'A');
    Opportunity oppTwo = new Opportunity(Name = 'B');

    String whereClause = 'Name > ' + oppOne.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @isTest
  static void shouldWorkForGreaterThanOrEqualStrings() {
    Opportunity oppOne = new Opportunity(Name = 'A');
    Opportunity oppTwo = new Opportunity(Name = 'B');

    String whereClause = 'Name >= ' + oppOne.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @isTest
  static void shouldWorkForLessThanDates() {
    Opportunity oppOne = new Opportunity(CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(CloseDate = System.today().addDays(-2));

    String whereClause = 'CloseDate < ' + oppTwo.CloseDate;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo));
  }

  @isTest
  static void shouldWorkForLessThanTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime < ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(false, eval.matches(cpa));
    System.assertEquals(false, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @isTest
  static void shouldWorkForLessThanDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime < ' + evOne.ActivityDateTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(false, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @isTest
  static void shouldWorkForLessThanOrEqualDates() {
    Opportunity oppOne = new Opportunity(CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(CloseDate = System.today().addDays(-2));

    String whereClause = 'CloseDate <= ' + oppTwo.CloseDate;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @isTest
  static void shouldWorkForLessThanOrEqualTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime <= ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(true, eval.matches(cpa));
    System.assertEquals(false, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @isTest
  static void shouldWorkForLessThanOrEqualsDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime <= ' + evOne.ActivityDateTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(true, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @isTest
  static void shouldWorkForLessThanStrings() {
    Opportunity oppOne = new Opportunity(Name = 'A');
    Opportunity oppTwo = new Opportunity(Name = 'B');

    String whereClause = 'Name < ' + oppTwo.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo));
  }

  @isTest
  static void shouldWorkForLessThanOrEqualStrings() {
    Opportunity oppOne = new Opportunity(Name = 'A');
    Opportunity oppTwo = new Opportunity(Name = 'A');

    String whereClause = 'Name <= ' + oppTwo.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
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
  static void shouldWorkForCurrencyZeros() {
    Account acc = new Account(AnnualRevenue = 0.00);
    String whereClause = 'AnnualRevenue != 0';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, acc.getSObjectType());

    System.assertNotEquals(true, eval.matches(acc));
  }

  @isTest
  static void shouldWorkForBooleanConditions() {
    User active = new User(IsActive = true);
    User nonActive = new User(IsActive = false);

    String lowerWhere = 'IsActive = true';
    String upperWhere = 'IsActive = TRUE';
    String mixedCase = 'IsActive = True';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(lowerWhere, active.getSObjectType());

    System.assertEquals(true, eval.matches(active));
    System.assertNotEquals(true, eval.matches(nonActive));

    eval = new RollupEvaluator.WhereFieldEvaluator(upperWhere, active.getSObjectType());

    System.assertEquals(true, eval.matches(active), 'Upper TRUE should match');
    System.assertNotEquals(true, eval.matches(nonActive), 'Upper TRUE should not match');

    eval = new RollupEvaluator.WhereFieldEvaluator(mixedCase, active.getSObjectType());

    System.assertEquals(true, eval.matches(active), 'Mixed case True should match');
    System.assertNotEquals(true, eval.matches(nonActive), 'Mixed case True should not match');
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
  static void shouldCorrectlyIdentifyIncludesForMultiSelectPicklists() {
    // QuickText.Channel is the only multi-select picklist in a vanilla Salesforce org
    QuickText qt = new QuickText(Channel = 'AAA;BBB;CCC');
    QuickText nonMatch = new QuickText(Channel = 'AAA');
    String whereClause = 'Channel INCLUDES (\'AAA;CCC\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, QuickText.SObjectType);
    System.assertEquals(true, eval.matches(qt), 'Channel should match');
    System.assertNotEquals(true, eval.matches(nonMatch), 'Does not have full picklist val, should not match');
  }

  @isTest
  static void shouldReturnDualEvaluatorWhenCalcItemChangedFieldsAndWhereClauseFilledOut() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, StageName = 'Updated Name');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.StageName = 'Old Name';

    Opportunity secondOpp = new Opportunity(Id = '0066g000000000000Z', StageName = 'Same', Amount = 25);

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      ChangedFieldsOnCalcItem__c = 'StageName',
      CalcItemWhereClause__c = 'Amount > 20',
      RollupOperation__c = Rollup.Op.SUM.name()
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp, secondOpp.Id => new Opportunity(Id = secondOpp.Id, StageName = secondOpp.StageName, Amount = 15) },
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

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      LookupFieldOnCalcItem__c = 'AccountId',
      CalcItemWhereClause__c = 'Amount > 20',
      RollupOperation__c = Rollup.Op.SUM.name()
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(null, rollupMetadata, new Map<Id, SObject>{ oldOpp.Id => oldOpp }, Opportunity.SObjectType);
    System.assertEquals(true, eval.matches(opp), 'Should match since StageName has changed and amount > 20');
  }

  @isTest
  static void shouldReturnDualEvaluatorWhenEvalIsPassedInAndReparenting() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', AccountId = '0016g000000000000X', Amount = 50);
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.AccountId = '0013g000000000000Z';

    Rollup__mdt rollupMetadata = new Rollup__mdt(LookupFieldOnCalcItem__c = 'AccountId', RollupOperation__c = Rollup.Op.SUM.name());

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp },
      Opportunity.SObjectType
    );
    System.assertEquals(true, eval.matches(opp), 'Should match since always true eval passed in and reparented');
  }

  @isTest
  static void shouldReturnChangedFieldEval() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50);
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.Amount = 25;

    Opportunity secondOpp = new Opportunity(Id = '0066g000000000000Z', Amount = 15);

    Rollup__mdt rollupMetadata = new Rollup__mdt(ChangedFieldsOnCalcItem__c = 'Amount', RollupOperation__c = Rollup.Op.SUM.name());

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      // second opp can't be passed by reference since we do a referential equality check in the changed field eval
      new Map<Id, SObject>{ oldOpp.Id => oldOpp, secondOpp.Id => new Opportunity(Id = secondOpp.Id, Amount = secondOpp.Amount, Name = 'Something else') },
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should match since amount changed');
    System.assertNotEquals(true, eval.matches(secondOpp), 'Should not match amount did not change');
  }

  @isTest
  static void shouldReturnDualEvaluatorWhenEvalIsPassedAndCalcItemWhereClause() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50);
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.StageName = 'Old Name';

    Opportunity secondOpp = new Opportunity(Id = '0066g000000000000Z', Amount = 15);

    Rollup__mdt rollupMetadata = new Rollup__mdt(CalcItemWhereClause__c = 'Amount > 20', RollupOperation__c = Rollup.Op.SUM.name());

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp, secondOpp.Id => secondOpp },
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should match since amount is > 20');
    System.assertNotEquals(true, eval.matches(secondOpp), 'Should not match since amount is < 20');
  }

  @isTest
  static void shouldReturnDoubleDualEvalWhenEvalIsPassedAndCalcItemWhereClauseAndChangedFields() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, StageName = 'Updated Name');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.StageName = 'Old Name';

    Opportunity secondOpp = new Opportunity(Id = '0066g000000000000Z', StageName = 'Same', Amount = 25);

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      ChangedFieldsOnCalcItem__c = 'StageName',
      CalcItemWhereClause__c = 'Amount > 20',
      RollupOperation__c = Rollup.Op.SUM.name()
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{
        oldOpp.Id => oldOpp,
        secondOpp.Id => new Opportunity(Id = secondOpp.Id, StageName = secondOpp.StageName, Amount = secondOpp.Amount, Name = 'Something else')
      },
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should match since StageName has changed and amount > 20');
    System.assertNotEquals(true, eval.matches(secondOpp), 'Should not match since StageName has not changed');
  }

  @isTest
  static void shouldNotReturnRelationshipFieldsIfTheyAreNotDirectlyRelated() {
    String queryString = 'User.Id IN (\'0056g000002GeR0AAA\')';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryString, Opportunity.SObjectType);

    System.assertEquals(new List<String>(), eval.getQueryFields());
  }

  @isTest
  static void shouldReturnOwnerParentFieldsWhenNotPolymorphic() {
    String queryString = 'Owner.Name = \'someName\'';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryString, Account.SObjectType);

    System.assertEquals(new List<String>{ 'Owner.Name' }, eval.getQueryFields());
  }

  @isTest
  static void shouldThrowExceptionForImproperlyEnteredWhereClause() {
    assertExceptionContains('= 1', 'Where clause entered incorrectly', null);
  }

  @isTest
  static void shouldThrowExceptionForMultipleValuesWithGreaterThan() {
    assertExceptionContains('Amount > (1, 2, 3, 4)', 'Comparison not valid with multiple arguments', new Opportunity(Amount = 1));
  }

  @isTest
  static void shouldThrowExceptionForMultipleValuesWithLessThan() {
    assertExceptionContains('Amount < (1, 2, 3, 4)', 'Comparison not valid with multiple arguments', new Opportunity(Amount = 1));
  }

  private static void assertExceptionContains(String whereClause, String expectedException, Opportunity opp) {
    Exception ex;

    try {
      RollupEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);
      eval.matches(opp);
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
    System.assertEquals(true, ex.getMessage().contains(expectedException));
  }

  @isTest
  static void shouldFilterRecursiveUpdates() {
    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId'
      ),
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, AccountId = '0016g000000000000X');

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');
    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive twice!');
    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive thrice!');

    RollupEvaluator.stubRequestId = 'somethingElse';

    eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId'
      ),
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );

    System.assertEquals(false, eval.matches(opp), 'Should not return true when recursive');
  }

  @isTest
  static void shouldNotFilterRecursiveUpdatesWhenGrandparentRelationshipFieldFilledOut() {
    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        GrandparentRelationshipFieldPath__c = 'Some.Field.Path'
      ),
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, AccountId = '0016g000000000000X');

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId'
      ),
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when recursive and grandparent field path filled out');
  }

  @isTest
  static void shouldNotFilterRecursiveUpdatesWhenRollupToUltimateParentIsTrue() {
    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        RollupToUltimateParent__c = true
      ),
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, AccountId = '0016g000000000000X');

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId'
      ),
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when recursive and ultimate parent field true');
  }

  @isTest
  static void shouldWorkWithTripleEvaluator() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, StageName = 'Updated Name', AccountId = '0016g000000000000X');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.StageName = 'Old Name';

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
      ChangedFieldsOnCalcItem__c = 'StageName',
      CalcItemWhereClause__c = 'Amount > 20',
      RollupFieldOnCalcItem__c = 'Amount',
      LookupFieldOnCalcItem__c = 'AccountId'
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp },
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    RollupEvaluator.stubRequestId = 'somethingElse';
    eval = RollupEvaluator.getEvaluator(null, rollupMetadata, new Map<Id, SObject>{ oldOpp.Id => oldOpp }, Opportunity.SObjectType);

    System.assertEquals(false, eval.matches(opp), 'Should not return true when recursive and all other conditions true');
  }

  @isTest
  static void shouldWorkWithChangedFieldsAndRecursionDetection() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, StageName = 'Updated Name', AccountId = '0016g000000000000X');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.StageName = 'Old Name';

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
      ChangedFieldsOnCalcItem__c = 'StageName',
      RollupFieldOnCalcItem__c = 'Amount',
      LookupFieldOnCalcItem__c = 'AccountId'
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp },
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    RollupEvaluator.stubRequestId = 'somethingElse';
    eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp },
      Opportunity.SObjectType
    );

    System.assertEquals(false, eval.matches(opp), 'Should not return true when recursive and all other conditions true');
  }

  @isTest
  static void shouldWorkWithCalcItemWhereClauseAndRecursionDetection() {
    Opportunity opp = new Opportunity(Id = '0066g000000000000X', Amount = 50, AccountId = '0016g000000000000X');
    Opportunity nonMatchingOpp = new Opportunity(Id = '0066g000000000000Y', Amount = 15, AccountId = '0016g000000000000X');

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      RollupOperation__c = Rollup.Op.UPDATE_CONCAT_DISTINCT.name(),
      CalcItemWhereClause__c = 'Amount > 20',
      RollupFieldOnCalcItem__c = 'Amount',
      LookupFieldOnCalcItem__c = 'AccountId'
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>(),
      Opportunity.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    RollupEvaluator.stubRequestId = 'somethingElse';
    eval = RollupEvaluator.getEvaluator(new RollupEvaluator.AlwaysTrueEvaluator(), rollupMetadata, new Map<Id, SObject>(), Opportunity.SObjectType);

    System.assertEquals(false, eval.matches(opp), 'Should not return true when recursive and all other conditions true');
    System.assertEquals(false, eval.matches(nonMatchingOpp), 'Should not match to begin with based on calc item where clause');
  }

  @isTest
  static void shouldWorkForNotEqualNull() {
    Opportunity opp = new Opportunity(AccountId = '0016g000000000000X');
    String whereClause = 'AccountId != null';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(true, eval.matches(opp), 'Opp should match since it has account Id');
    System.assertNotEquals(true, eval.matches(new Opportunity()), 'Opp should not match since AccountId is null');
  }
}

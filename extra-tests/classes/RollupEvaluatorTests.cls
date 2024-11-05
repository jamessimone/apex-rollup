@IsTest
private class RollupEvaluatorTests {
  @IsTest
  static void shouldReturnEqualsCorrectlyForEqualsCriteria() {
    Opportunity nameEquals = new Opportunity(Name = 'RollupZ');
    Opportunity doesNotEqualName = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name = \'RollupZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'Name should match RollupZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'Name should not match RollupZ');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEquals() {
    Opportunity nameEquals = new Opportunity(Name = 'RollupZ');
    Opportunity doesNotEqualName = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name != \'RollupZZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'RollupZ should match since it does not equal RollupZZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'RollupZZ should not match');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEqualsAlternate() {
    Opportunity nameEquals = new Opportunity(Name = 'RollupZ');
    Opportunity doesNotEqualName = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name <> \'RollupZZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'RollupZ should match since it does not equal RollupZZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'RollupZZ should not match');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldEqualsMultiple() {
    Opportunity rollupZ = new Opportunity(Name = 'RollupZ');
    Opportunity rollupZZ = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name IN (\'RollupZZ\', \'RollupZ\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, rollupZ.getSObjectType());

    System.assertEquals(true, eval.matches(rollupZ), 'Should match based on IN');
    System.assertEquals(true, eval.matches(rollupZZ), 'Should match based on IN');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEqualsMultiple() {
    Opportunity rollupZ = new Opportunity(Name = 'RollupZ');
    Opportunity rollupZZ = new Opportunity(Name = 'RollupZZ');
    String whereClause = 'Name NOT IN (\'RollupZZ\', \'RollupZ\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, rollupZ.getSObjectType());

    System.assertNotEquals(true, eval.matches(rollupZ), 'Should not match based on NOT IN');
    System.assertNotEquals(true, eval.matches(rollupZZ), 'Should not match based on NOT IN');
  }

  @IsTest
  static void shouldFilterCalcItemsForNotEqualsNumbers() {
    Opportunity notZero = new Opportunity(Amount = 10);
    Opportunity zero = new Opportunity(Amount = 0);
    String whereClause = 'Amount != 0';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, zero.getSObjectType());

    System.assertEquals(true, eval.matches(notZero), String.valueOf(notZero.Amount) + ' should not = 0');
    System.assertNotEquals(true, eval.matches(zero), '0 should  be excluded since opp amount = ' + zero.Amount);
  }

  @IsTest
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

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForParentFields() {
    Account acc = new Account(Name = 'RollupEvaluatorTests');
    Opportunity oppOne = new Opportunity(Name = acc.Name, Account = acc);
    Opportunity oppTwo = new Opportunity(Name = 'RollupZ', Account = new Account(Name = 'Some other name'));
    String whereClause = 'Account.Name != ' + acc.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match since the name is different than the parent field name');
  }

  @IsTest
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

  @IsTest
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

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForLikeStatements() {
    Account acc = new Account(Name = 'RollupEvaluatorTest');
    Opportunity oppOne = new Opportunity(Name = 'RollupZZ', Account = acc);
    Opportunity oppTwo = new Opportunity(Name = 'RollupZ', Account = acc);

    String whereClause = 'Account.Name LIKE \'%Rollup%\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Should match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match based on parent field');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForNotLikeStatements() {
    Account acc = new Account(Name = 'RollupEvaluatorTest');
    Opportunity target = new Opportunity(Name = 'RollupZZ', Account = acc);

    String whereClause = 'NOT Account.Name LIKE \'%Rollup%\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, target.getSObjectType());

    System.assertEquals(false, eval.matches(target));
    target.Account.Name = 'Rollup';
    System.assertEquals(false, eval.matches(target));
    target.Account.Name = 'rollUP';
    System.assertEquals(false, eval.matches(target));
    target.Account.Name = 'match';
    System.assertEquals(true, eval.matches(target));
  }

  @IsTest
  static void shouldProperlyDetectWildcardsForLike() {
    Opportunity target = new Opportunity(Name = 'Something new');

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator('Name LIKE \'thi%\'', Opportunity.SObjectType);

    System.assertEquals(false, eval.matches(target));
    System.assertEquals(true, eval.matches(new Opportunity(Name = 'thing')));

    eval = new RollupEvaluator.WhereFieldEvaluator('Name LIKE \'%thi%\'', Opportunity.SObjectType);
    System.assertEquals(true, eval.matches(target));

    eval = new RollupEvaluator.WhereFieldEvaluator('Name LIKE \'%t%i%\'', Opportunity.SObjectType);
    System.assertEquals(true, eval.matches(target));
    target.Name = 'Created From: Parent Initiated Rollup';
    System.assertEquals(true, eval.matches(target));
    target.Name = 'ti';
    System.assertEquals(true, eval.matches(target));
    target.Name = 'it';
    System.assertEquals(false, eval.matches(target));
  }

  @IsTest
  static void shouldFilterCalcItemsThatContainAndOrStringsThatAreNotFilterConditions() {
    Opportunity oppOne = new Opportunity(Name = 'A or B');
    Opportunity oppTwo = new Opportunity(Name = 'A and B');

    String whereClause = 'Name = \'A or B\''; // gasp

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Where clause should not have been split in the wrong place!');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Where clause should not have been split in the wrong place!');
  }

  @IsTest
  static void shouldWorkForStringsWithSymbolsInThem() {
    Opportunity oppOne = new Opportunity(Name = '!()eeeek$$$-@');

    String whereClause = 'Name = \'!()eeeek$$$-@\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Where clause should not have been split in the wrong place!');
  }

  @IsTest
  static void shouldWorkForParanthesisAtEndOfString() {
    Opportunity nameWithParanthesis = new Opportunity(Name = 'Realized Gain/(Loss)');

    String whereClause = 'Name = \'Realized Gain/(Loss)\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameWithParanthesis.getSObjectType());

    System.assertEquals(true, eval.matches(nameWithParanthesis), 'Where clause should not have been split in the wrong place!');
  }

  @IsTest
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

  @IsTest
  static void shouldWorkForGreaterThanDates() {
    Opportunity oppOne = new Opportunity(CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(CloseDate = System.today().addDays(-2));

    String whereClause = 'CloseDate > ' + getSoqlCompliantDatetime(Datetime.newInstance(oppTwo.CloseDate, Time.newInstance(0, 0, 0, 0)));

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo), 'Second close date should not match since it is not greater: ' + oppTwo.CloseDate);
  }

  @IsTest
  static void shouldWorkForGreaterThanDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now().addSeconds(-1));
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(2));

    String whereClause = 'ActivityDateTime > ' + getSoqlCompliantDatetime(System.now());

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(false, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @IsTest
  static void shouldWorkForGreaterThanTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime > ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(false, eval.matches(cpa));
    System.assertEquals(true, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @IsTest
  static void shouldWorkForGreaterThanOrEqualDates() {
    Opportunity oppOne = new Opportunity(CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(CloseDate = System.today().addDays(-2));

    String whereClause = 'CloseDate >= ' + getSoqlCompliantDatetime(Datetime.newInstance(oppTwo.CloseDate, Time.newInstance(0, 0, 0, 0)));

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForGreaterThanOrEqualsTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime >= ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(true, eval.matches(cpa));
    System.assertEquals(true, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @IsTest
  static void shouldWorkForGreaterThanOrEqualsDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime >= ' + getSoqlCompliantDatetime(evOne.ActivityDateTime);

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(true, eval.matches(evOne));
    System.assertEquals(false, eval.matches(evTwo));
  }

  @IsTest
  static void shouldWorkForGreaterThanStrings() {
    Opportunity oppOne = new Opportunity(Name = 'A');
    Opportunity oppTwo = new Opportunity(Name = 'B');

    String whereClause = 'Name > ' + oppOne.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForGreaterThanOrEqualStrings() {
    Opportunity oppOne = new Opportunity(Name = 'A');
    Opportunity oppTwo = new Opportunity(Name = 'B');

    String whereClause = 'Name >= ' + oppOne.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanDates() {
    Opportunity oppOne = new Opportunity(CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(CloseDate = System.today().addDays(-2));

    String whereClause = 'CloseDate < ' + getSoqlCompliantDatetime(Datetime.newInstance(oppTwo.CloseDate, Time.newInstance(0, 0, 0, 0)));

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime < ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(false, eval.matches(cpa));
    System.assertEquals(false, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @IsTest
  static void shouldWorkForLessThanDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime < ' + getSoqlCompliantDatetime(evOne.ActivityDateTime);

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(false, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @IsTest
  static void shouldWorkForLessThanOrEqualDates() {
    Opportunity oppOne = new Opportunity(CloseDate = System.today());
    Opportunity oppTwo = new Opportunity(CloseDate = System.today().addDays(-2));

    String whereClause = 'CloseDate <= ' + getSoqlCompliantDatetime(Datetime.newInstance(oppTwo.CloseDate, Time.newInstance(0, 0, 0, 0)));

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanOrEqualTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime <= ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(true, eval.matches(cpa));
    System.assertEquals(false, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @IsTest
  static void shouldWorkForLessThanOrEqualsDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime <= ' + getSoqlCompliantDatetime(evOne.ActivityDateTime);

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(true, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @IsTest
  static void shouldWorkForLessThanStrings() {
    Opportunity oppOne = new Opportunity(Name = 'A');
    Opportunity oppTwo = new Opportunity(Name = 'B');

    String whereClause = 'Name < ' + oppTwo.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanOrEqualStrings() {
    Opportunity oppOne = new Opportunity(Name = 'A');
    Opportunity oppTwo = new Opportunity(Name = 'A');

    String whereClause = 'Name <= ' + oppTwo.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
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

  @IsTest
  static void shouldWorkForCurrencyZeros() {
    Account acc = new Account(AnnualRevenue = 0.00);
    String whereClause = 'AnnualRevenue != 0';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, acc.getSObjectType());

    System.assertNotEquals(true, eval.matches(acc));
  }

  @IsTest
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

  @IsTest
  static void shouldReturnForMultipleOrConditionalsWithQueryKeywordsInString() {
    Opportunity oppOne = new Opportunity(ForecastCategoryName = 'Omitted');
    Opportunity oppTwo = new Opportunity(ForecastCategoryName = 'Pipeline'); // pipeline has "in" within it; this is a query keyword that should not get replaced
    Opportunity oppThree = new Opportunity(ForecastCategoryName = 'Best Case');
    Opportunity oppFour = new Opportunity(ForecastCategoryName = 'Commit');
    Opportunity oppFive = new Opportunity(Amount = 5, ForecastCategoryName = 'Closed');

    String whereClause = 'ForecastCategoryName = \'Omitted\' OR ForecastCategoryName = \'Best Case\' OR ForecastCategoryName = \'Pipeline\' OR Amount = 5';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(true, eval.matches(oppOne), 'ForecastCategoryName for opp one should match');
    System.assertEquals(true, eval.matches(oppTwo), 'ForecastCategoryName for opp two should match');
    System.assertEquals(true, eval.matches(oppThree), 'ForecastCategoryName for opp three should match');
    System.assertEquals(false, eval.matches(oppFour), 'ForecastCategoryName for opp four should not match');
    System.assertEquals(true, eval.matches(oppFive), 'Amount for opp five should match');
  }

  @IsTest
  static void shouldReturnCorrectlyWhenQueryKeywordsWithSpacesArePartOfString() {
    // even worse than the above - imagine a Name field "This in That" returning false
    // because we've mistakenly transformed it into "This = that" 🤦‍♂️
    Opportunity nameShouldMatch = new Opportunity(Name = 'This in That');
    String whereClause = 'Name = \'This in That\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);
    System.assertEquals(true, eval.matches(nameShouldMatch), 'Name should match');
  }

  @IsTest
  static void shouldCorrectlyIdentifyIncludesForMultiSelectPicklists() {
    // QuickText.Channel is the only multi-select picklist in a vanilla Salesforce org
    QuickText qt = new QuickText(Channel = 'AAA;BBB;CCC');
    QuickText nonMatch = new QuickText(Channel = 'AAA');
    String whereClause = 'Channel INCLUDES (\'AAA;CCC\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, QuickText.SObjectType);
    System.assertEquals(true, eval.matches(qt), 'Channel should match');
    System.assertNotEquals(true, eval.matches(nonMatch), 'Does not have full picklist val, should not match');
  }

  @IsTest
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

  @IsTest
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

  @IsTest
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

  @IsTest
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

  @IsTest
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

  @IsTest
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

  @IsTest
  static void shouldNotReturnRelationshipFieldsIfTheyAreNotDirectlyRelated() {
    String queryString = 'User.Id IN (\'0056g000002GeR0AAA\')';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryString, Opportunity.SObjectType);

    System.assertEquals(new List<String>(), eval.getQueryFields());
  }

  @IsTest
  static void shouldReturnOwnerParentFieldsWhenNotPolymorphic() {
    String queryString = 'Owner.Name = \'someName\'';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryString, Account.SObjectType);

    System.assertEquals(new List<String>{ 'Owner.Name' }, eval.getQueryFields());
  }

  @IsTest
  static void shouldReturnDateFunctionFields() {
    String queryString = 'HOUR_IN_DAY(CreatedDate) = 15';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryString, Account.SObjectType);
    System.assertEquals(new List<String>{ 'CreatedDate' }, eval.getQueryFields());
  }

  @IsTest
  static void shouldThrowExceptionForImproperlyEnteredWhereClause() {
    Exception ex;
    try {
      RollupEvaluator eval = new RollupEvaluator.WhereFieldEvaluator('= 1', Opportunity.SObjectType);
      eval.matches(null);
      Assert.fail('Exception should be thrown above');
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(true, ex?.getMessage().contains('Where clause entered incorrectly'));
  }

  @IsTest
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

  @IsTest
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

  @IsTest
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

  @IsTest
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

  @IsTest
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

  @IsTest
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
    System.assertEquals(false, eval.matches(nonMatchingOpp), 'Should not match to begin with based on child object where clause');
  }

  @IsTest
  static void shouldWorkForNotEqualNull() {
    Opportunity opp = new Opportunity(AccountId = '0016g000000000000X');
    String whereClause = 'AccountId != null';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(true, eval.matches(opp), 'Opp should match since it has account Id');
    System.assertNotEquals(true, eval.matches(new Opportunity()), 'Opp should not match since AccountId is null');
  }

  @IsTest
  static void shouldCorrectlyDetectNestedNot() {
    String whereClause = 'TaskSubType != \'Email\' OR (NOT Subject LIKE \'Email\')';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Task.SObjectType);

    System.assertEquals(true, eval.matches(new Task(TaskSubType = 'Call')));
    System.assertEquals(true, eval.matches(new Task(TaskSubType = 'Email', Subject = 'Hello')));
    System.assertEquals(false, eval.matches(new Task(TaskSubType = 'Email', Subject = 'Email')));
    System.assertEquals(true, eval.matches(new Task()));
  }

  @IsTest
  static void shouldDetectNestedNotOrConditions() {
    String whereClause = 'Amount = 1 OR (NOT (Amount = 0 OR Amount = 5))';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(false, eval.matches(new Opportunity(Amount = 0)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 1)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 2)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 3)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 4)));
    System.assertEquals(false, eval.matches(new Opportunity(Amount = 5)));
  }

  @IsTest
  static void shouldDetectNestedNotAndConditions() {
    String whereClause = 'Amount >= 1 AND (NOT(Amount = 0 OR Amount = 5))';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(false, eval.matches(new Opportunity(Amount = 0)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 1)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 2)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 3)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 4)));
    System.assertEquals(false, eval.matches(new Opportunity(Amount = 5)));
  }

  @IsTest
  static void shouldDetectNotInProperly() {
    String whereClause = 'Amount NOT IN (1, 3)';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(true, eval.matches(new Opportunity(Amount = 0)));
    System.assertEquals(false, eval.matches(new Opportunity(Amount = 1)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 2)));
    System.assertEquals(false, eval.matches(new Opportunity(Amount = 3)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 4)));
  }

  @IsTest
  static void shouldNotMangleValuesWithNameInThem() {
    String whereClause = 'Name != \'oneName\'';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointAddress.SObjectType);

    System.assertEquals(false, eval.matches(new ContactPointAddress(Name = 'oneName')));
  }

  @IsTest
  static void shouldWorkWithCarriageReturnsAndLineBreaks() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    String whereClause = 'Name = \'someValue\' AND (PreferenceRank = 1 \r\n OR PreferenceRank = 2 \r\n OR PreferenceRank = 3)';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointAddress.SObjectType);

    System.assertEquals(true, eval.matches(new ContactPointAddress(Name = 'someValue', PreferenceRank = 1)));
    System.assertEquals(false, eval.matches(new ContactPointAddress(Name = 'someValue', PreferenceRank = 0)), 'cpa should not match');
    System.assertEquals(false, eval.matches(new ContactPointAddress(Name = 'someValue', PreferenceRank = 4)), 'preference rank should not match');
    System.assertEquals(true, eval.matches(new ContactPointAddress(Name = 'someValue', PreferenceRank = 3)));
  }

  @IsTest
  static void shouldWorkWithoutDecimalZeroesForNumbers() {
    String whereClause = 'Amount = 50000';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(true, eval.matches(new Opportunity(Amount = 50000)));
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 50000.00)), 'Should work with or without decimal places');
    System.assertEquals(false, eval.matches(new Opportunity(Amount = 50000.01)));

    eval = new RollupEvaluator.WhereFieldEvaluator('Amount = 50.1', Opportunity.SObjectType);
    System.assertEquals(true, eval.matches(new Opportunity(Amount = 50.10)), 'Should detect trailing zero correctly');
  }

  @IsTest
  static void shouldProperlySupportNonPolymorphicOwnerClauses() {
    String whereClause = 'Account.Owner.Id != null';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);
    System.assertEquals('Account.Owner.Id', eval.getQueryFields()[0]);
  }

  @IsTest
  static void shouldNotPassOwnerInQueryFieldsForPolymorphicField() {
    String whereClause = 'Parent.Owner.Id != null';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointAddress.SObjectType);
    System.assertEquals(0, eval.getQueryFields().size(), 'Should not return polymorphic field');
  }

  @IsTest
  static void shouldProperlyReturnMultipleParentLevelFields() {
    String whereClause = 'Account.Name != null AND Account.Owner.Id != null';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);
    List<String> queryFields = eval.getQueryFields();
    System.assertEquals(2, queryFields.size(), 'Both fields should have been returned: ' + queryFields);
    System.assertEquals('Account.Name', queryFields[0]);
    System.assertEquals('Account.Owner.Id', queryFields[1]);
  }

  @IsTest
  static void returnsLowercaseParentLevelFields() {
    String whereClause = 'opportunity.account.name = \'some account\'';
    List<String> queryFields = new RollupEvaluator.WhereFieldEvaluator(whereClause, OpportunityLineItem.SObjectType).getQueryFields();
    System.assertEquals(1, queryFields.size(), queryFields);
    System.assertEquals('opportunity.account.name', queryFields[0]);
  }

  @IsTest
  static void supportsNonPolymorphicTypeFields() {
    String whereClause = 'Campaign.Type <> \'Something Else\'';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);
    List<String> queryFields = eval.getQueryFields();
    System.assertEquals(1, queryFields.size(), queryFields);
    System.assertEquals('Campaign.Type', queryFields[0]);
  }

  @IsTest
  static void supportsTypeFieldWhenOnlyPresentOnParent() {
    String whereClause = 'Account.Type != \'Something\'';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Contact.SObjectType);
    List<String> queryFields = eval.getQueryFields();
    System.assertEquals(1, queryFields.size(), queryFields);
    System.assertEquals('Account.Type', queryFields[0]);
  }

  @IsTest
  static void gracefullyHandlesFieldNotExistingForDateLiteral() {
    String whereClause = 'SomeFieldThatDoesNotExist = THIS_YEAR';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(false, eval.matches(new Opportunity()));
  }

  @IsTest
  static void shouldProperlyEvaluateDateLiteral() {
    String whereClause = 'CloseDate = THIS_YEAR';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);
    System.assertEquals(true, eval.matches(new Opportunity(CloseDate = System.today())));
    System.assertEquals(false, eval.matches(new Opportunity(CloseDate = System.today().addYears(-1))));
  }

  @IsTest
  static void shouldProperlyEvaluateDateFunction() {
    String whereClause = 'HOUR_IN_DAY(ReminderDateTime) = 5';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Task.SObjectType);
    Time fifthHour = Time.newInstance(5, 0, 0, 0);
    Datetime fifthHourDt = Datetime.newInstanceGmt(System.today(), fifthHour);
    System.assertEquals(true, eval.matches(new Task(ReminderDateTime = fifthHourDt)));
  }

  @IsTest
  static void shouldProperlyEvaluateLiteralDateFunctions() {
    Date comparisonDate = Date.newInstance(2020, 3, 7);
    String whereClause = 'DAY_ONLY(ReminderDateTime) = 2020-03-07';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Task.SObjectType);
    System.assertEquals(true, eval.matches(new Task(ReminderDateTime = Datetime.newInstanceGmt(comparisonDate, Time.newInstance(0, 0, 0, 0)))));
  }

  @IsTest
  static void shouldStripAwayRelationshipNameWhenParentClauseAndTypeMatchesParent() {
    String whereClause = 'Account.AnnualRevenue = 5';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Account.SObjectType);
    System.assertEquals(true, eval.matches(new Account(AnnualRevenue = 5)));
  }

  @IsTest
  static void shouldNotBlowUpOnRelationshipNameForDifferentParent() {
    String whereClause = 'Asset.AssetLevel = 1';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Account.SObjectType);
    System.assertEquals(true, eval.matches(new Account()));
  }

  @IsTest
  static void worksWithNYearsAgo() {
    Id accountId = RollupTestUtils.createId(Account.SObjectType);
    String whereClause =
      'AccountId = \'' +
      accountId +
      '\' AND CloseDate <= LAST_YEAR AND CloseDate > N_YEARS_AGO:3 AND StageName != \'Closed Lost\' AND StageName != \'Closed/No Event Fees Only\'';
    Opportunity matchingOpp = new Opportunity(AccountId = accountId, CloseDate = System.today().addYears(-1));
    Opportunity stageClosedLostNonMatch = new Opportunity(AccountId = accountId, CloseDate = System.today().addYears(-2), StageName = 'Closed Lost');
    Opportunity stageClosedNonMatch = new Opportunity(AccountId = accountId, CloseDate = System.today().addYears(-2), StageName = 'Closed/No Event Fees Only');
    Opportunity idNonMatch = new Opportunity(CloseDate = System.today().addYears(-2));
    Opportunity closeDateNonMatch = new Opportunity(CloseDate = System.today(), AccountId = accountId);

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    System.assertEquals(true, eval.matches(matchingOpp));
    System.assertEquals(false, eval.matches(stageClosedLostNonMatch));
    System.assertEquals(false, eval.matches(stageClosedNonMatch));
    System.assertEquals(false, eval.matches(idNonMatch));
    System.assertEquals(false, eval.matches(closeDateNonMatch));
  }

  @IsTest
  static void stringsAreComparedCaseInsensitive() {
    String whereClause = 'StageName = \'closed lost\'';
    Opportunity opp = new Opportunity(StageName = 'Closed Lost');

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, opp.getSObjectType());

    System.assertEquals(true, eval.matches(opp));
  }

  @IsTest
  static void pascalCaseForFieldNamesIsNotRequired() {
    String poorlyCasedFieldName = Opportunity.IsClosed.toString().toLowerCase();

    Opportunity isClosedFalse = (Opportunity) JSON.deserialize('{ "IsClosed": false }', Opportunity.class);
    OpportunityLineItem target = new OpportunityLineItem(Opportunity = isClosedFalse);
    System.assertEquals(false, target.Opportunity.IsClosed);
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(
      'Opportunity.' + poorlyCasedFieldName + ' = false',
      target.getSObjectType()
    );

    System.assertEquals(true, eval.matches(target));
    System.assertEquals(false, eval.matches(new OpportunityLineItem()), 'Should properly evaluate for null relationship');
  }

  @IsTest
  static void nestedConditionalsWork() {
    String whereClause = '((IsActive = TRUE) OR (IsActive = FALSE AND FirstName = \'One\') OR (IsActive = FALSE AND FirstName LIKE \'Special%\') OR (FirstName = \'a\' AND AboutMe = \'b\') OR (FirstName = \'b\'))';
    User target = new User(IsActive = false, FirstName = 'One');

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, target.getSObjectType());

    validateQuery(User.SObjectType, whereClause);
    System.assertEquals(true, eval.matches(target));
    System.assertEquals(true, eval.matches(new User(IsActive = true)));
    System.assertEquals(true, eval.matches(new User(IsActive = false, FirstName = 'SpecialK')));
    System.assertEquals(true, eval.matches(new User(FirstName = 'a', AboutMe = 'b')));
    System.assertEquals(true, eval.matches(new User(FirstName = 'b')));
    System.assertEquals(false, eval.matches(new User(IsActive = false, FirstName = 'c')));
  }

  @IsTest
  static void nestedConditionalsWorkWithSomeMatchingInnerClauses() {
    String whereClause = '(StageName = \'one\' AND LeadSource IN (\'Web\', \'Phone\') ) OR (LeadSource in (\'Web\', \'Phone\') AND StageName = \'two\')';

    Opportunity target = new Opportunity(StageName = 'one', LeadSource = 'Web');
    Opportunity secondMatch = new Opportunity(StageName = 'two', LeadSource = 'Phone');
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, target.getSObjectType());

    validateQuery(Opportunity.SObjectType, whereClause);
    System.assertEquals(true, eval.matches(target));
    System.assertEquals(true, eval.matches(secondMatch));
    System.assertEquals(false, eval.matches(new Opportunity(StageName = 'three', LeadSource = 'Web')));
  }

  @IsTest
  static void nestedConditionalsWorkWithMoreThanOneLevel() {
    Opportunity oppOne = new Opportunity(StageName = 'Not A Match');
    Opportunity oppTwo = new Opportunity(Amount = 5, StageName = 'Hi');
    Opportunity oppThree = new Opportunity(Amount = 3.01, StageName = 'Hello there');
    Opportunity oppFour = new Opportunity(StageName = 'Hi', Amount = 0);
    Opportunity oppFive = new Opportunity(Id = '0066g000000000000T', Amount = 3.99999);

    String whereClause =
      'Amount < 4 AND (StageName LIKE \'%Hello%\' OR StageName = \'Hi\' OR (Id IN (\'' +
      oppFive.Id +
      '\',' +
      '\'0066g000000000000Z\'' +
      ')' +
      ' AND Amount = ' +
      oppFive.Amount +
      '))';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Opportunity.SObjectType);

    validateQuery(Opportunity.SObjectType, whereClause);
    System.assertNotEquals(true, eval.matches(oppOne), 'Name does not match!');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Amount does not match');
    System.assertEquals(true, eval.matches(oppThree), 'Amount matches and name roughly matches!');
    System.assertEquals(true, eval.matches(oppFour), 'Amount and name match');
    System.assertEquals(true, eval.matches(oppFive), 'Id matches inner nested conditional!');
  }

  @IsTest
  static void nestedConditionalWorksWithInSpaces() {
    String whereClause = 'PrivacyConsentStatus = \'Yes\' and EffectiveTo <= TODAY and Effectivefrom >= TODAY and CaptureSource in ( \'Hi\' , \'Hello\' , \'Hola\') and (Name = \'excellent\' or Name = \'stellar\')';

    ContactPointConsent match1 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now().addDays(-1),
      EffectiveFrom = System.now(),
      CaptureSource = 'Hi',
      Name = 'Excellent'
    );
    ContactPointConsent match2 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now().addDays(-1),
      EffectiveFrom = System.now(),
      CaptureSource = 'hello',
      Name = 'stellar'
    );
    ContactPointConsent match3 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now().addDays(-1),
      EffectiveFrom = System.now(),
      CaptureSource = 'Hola',
      Name = 'stellar'
    );
    ContactPointConsent nonMatch1 = new ContactPointConsent(
      PrivacyConsentStatus = 'nonmatch',
      EffectiveTo = System.now().addDays(2),
      EffectiveFrom = System.now().addDays(-1),
      CaptureSource = 'Hi',
      Name = 'stellar'
    );
    ContactPointConsent nonMatch2 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now(),
      EffectiveFrom = System.now().addDays(-1),
      CaptureSource = 'nonmatch',
      Name = 'stellar'
    );
    ContactPointConsent nonMatch3 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now(),
      EffectiveFrom = System.now().addDays(-1),
      CaptureSource = 'hi',
      Name = 'nonmatch'
    );

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointConsent.SObjectType);

    System.assertEquals(true, eval.matches(match1));
    System.assertEquals(true, eval.matches(match2));
    System.assertEquals(true, eval.matches(match3));
    System.assertEquals(false, eval.matches(nonMatch1));
    System.assertEquals(false, eval.matches(nonMatch2));
    System.assertEquals(false, eval.matches(nonMatch3));
  }

  @IsTest
  static void stripsExtraParantheticalStructures() {
    String whereClause = '(Name IN (\'0-Current\', \'1-30 Days\', \'31-60 Days\')) AND Name IN (\'0-Current\', \'1-30 Days\', \'31-60 Days\')';

    RollupEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointConsent.SObjectType);

    System.assertEquals(true, eval.matches(new ContactPointConsent(Name = '0-Current')));
  }

  private static String getSoqlCompliantDatetime(Datetime dt) {
    return dt.format('yyyy-MM-dd\'T\'HH:mm:ssZ');
  }

  private static void validateQuery(Schema.SObjectType target, String whereClause) {
    // sanity check - is the where clause valid?
    Database.query('SELECT Id FROM ' + target + ' WHERE ' + whereClause);
  }
}

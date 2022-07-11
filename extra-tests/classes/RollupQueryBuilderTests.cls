@SuppressWarnings('PMD.UnusedLocalVariable')
@IsTest
private class RollupQueryBuilderTests {
  private static final Set<String> objIds = new Set<String>();
  @IsTest
  static void shouldQueryAllTasks() {
    String queryString = RollupQueryBuilder.Current.getQuery(Task.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    // validate the query
    List<SObject> records = Database.query(queryString);

    System.assertEquals(true, queryString.contains('AND IsDeleted = false ALL ROWS'));
    System.assertEquals(Task.SObjectType, records.getSObjectType());
  }

  @IsTest
  static void shouldQueryAllEvents() {
    String queryString = RollupQueryBuilder.Current.getQuery(Event.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    Set<String> objIds = new Set<String>();
    List<SObject> records = Database.query(queryString);

    System.assertEquals(true, queryString.contains('AND IsDeleted = false ALL ROWS'));
    System.assertEquals(Event.SObjectType, records.getSObjectType());
  }

  @IsTest
  static void shouldProperlyQueryIfMultipleCasedVersionsOfSameFieldPassedIn() {
    String queryString = RollupQueryBuilder.Current.getQuery(
      Opportunity.SObjectType,
      new List<String>{ 'Id', 'ID', 'id', 'iD', 'AccountId', 'AccountID', 'accountId', 'accountID' },
      'AccountId',
      '='
    );

    List<SObject> records = Database.query(queryString);

    System.assertEquals(true, queryString.contains('Id'));
    System.assertEquals(true, queryString.contains('AccountId'));
    System.assertEquals(Opportunity.SObjectType, records.getSObjectType());
  }

  @IsTest
  static void shouldNotBlowUpIfPassedInFieldsAreNullOrBlank() {
    String queryString = RollupQueryBuilder.Current.getQuery(Opportunity.SObjectType, new List<String>{ '', null, ' ', 'Id' }, 'AccountId', '=');

    List<SObject> records = Database.query(queryString);

    System.assertEquals(true, queryString.contains('Id'));
    System.assertEquals(Opportunity.SObjectType, records.getSObjectType());
  }

  @IsTest
  static void shouldHandleNestedPolymporphicWhereClauses() {
    // we expect that What.Type will end up being stripped out of this
    // where clause; this is only true for polymorphic where clauses
    String queryString = RollupQueryBuilder.Current.getQuery(
      Event.SObjectType,
      new List<String>{ 'Subject', 'WhatId' },
      Event.WhatId.getDescribe().getName(),
      '!=',
      '((What.Type = \'Account\') AND What.Owner.Id = :recordIds)'
    );

    System.assertEquals(true, queryString.contains('TYPEOF'), 'Polymorphic where clause should have been transformed: ' + queryString);
    System.assertEquals(false, queryString.contains('What.Owner.Id'));
    System.assertEquals(false, queryString.contains('()'), 'Should clean up removed nested conditionals: ' + queryString);
    System.assertEquals(false, queryString.contains('AND  AND '), queryString);
    System.assertEquals(false, queryString.contains('What.Type'), 'What.Type should have been stripped out: ' + queryString);
    Set<String> recordIds = new Set<String>();
    Set<String> objIds = recordIds;
    // confirm query works
    List<SObject> records = Database.query(queryString);
    System.assertEquals(Event.SObjectType, records.getSObjectType());
  }

  @IsTest
  static void shouldWrapTopLevelOrClauses() {
    String queryString = RollupQueryBuilder.Current.getQuery(
      Opportunity.SObjectType,
      new List<String>{ 'Amount' },
      Opportunity.AccountId.getDescribe().getName(),
      '=',
      'Amount > 0 OR CloseDate = YESTERDAY'
    );
    System.assert(queryString.contains('(Amount > 0 OR CloseDate = YESTERDAY)'), 'top-level OR clause should be wrapped');
  }

  @IsTest
  static void correctlyPutsAllRowsAtEnd() {
    String queryString =
      RollupQueryBuilder.Current.getQuery(Event.SObjectType, new List<String>{ 'Subject', 'WhatId' }, Event.WhatId.getDescribe().getName(), '!=') + '\nLIMIT 1';
    System.assertEquals(true, queryString.contains(RollupQueryBuilder.ALL_ROWS), 'Needs to have all rows in order to be valid');

    queryString = RollupQueryBuilder.Current.getAllRowSafeQuery(Event.SObjectType, queryString);

    System.assertEquals(true, queryString.endsWith(RollupQueryBuilder.ALL_ROWS));
    // validate query can be run
    Database.query(queryString);
  }

  @IsTest
  static void multiCurrencyOrgsAlwaysAddIsoCode() {
    RollupCurrencyInfo.IS_MULTICURRENCY = true;

    String queryString = RollupQueryBuilder.Current.getQuery(Account.SObjectType, new List<String>(), 'Id', '=');

    System.assertEquals(true, queryString.contains(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME));
  }
}

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
      Event.WhatId.toString(),
      '!=',
      '(((What.Type = \'Account\') AND What.Owner.Id = :recordIds))'
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
  static void handlesNestedPolymorphicWhereClausesWithOr() {
    // we expect that What.Type will end up being stripped out of this
    // where clause; this is only true for polymorphic where clauses
    String queryString = RollupQueryBuilder.Current.getQuery(
      Event.SObjectType,
      new List<String>{ 'Subject', 'WhatId' },
      Event.WhatId.toString(),
      '!=',
      '(((What.Type = \'Account\') OR What.Owner.Id = :recordIds))'
    );

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
      Opportunity.AccountId.toString(),
      '=',
      'Amount > 0 OR CloseDate = YESTERDAY'
    );
    System.assert(queryString.contains('(Amount > 0 OR CloseDate = YESTERDAY)'), 'top-level OR clause should be wrapped');
  }

  @IsTest
  static void correctlyPutsAllRowsAtEnd() {
    String queryString =
      RollupQueryBuilder.Current.getQuery(Event.SObjectType, new List<String>{ 'Subject', 'WhatId' }, Event.WhatId.toString(), '!=') + '\nLIMIT 1';
    System.assertEquals(true, queryString.contains(RollupQueryBuilder.ALL_ROWS), 'Needs to have all rows in order to be valid');

    queryString = RollupQueryBuilder.Current.getAllRowSafeQuery(Event.SObjectType, queryString);

    System.assertEquals(true, queryString.endsWith(RollupQueryBuilder.ALL_ROWS));
    // validate query can be run
    Database.query(queryString);
  }

  @IsTest
  static void multiCurrencyOrgsAddIsoCodeWhenIsoCodeExists() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }

    String queryString = RollupQueryBuilder.Current.getQuery(Account.SObjectType, new List<String>(), 'Id', '=');

    System.assertEquals(true, queryString.contains(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME));
  }

  @IsTest
  static void doesNotAddIsoCodeForMultiCurrencyWhenFieldDoesNotExist() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }

    String queryString = RollupQueryBuilder.Current.getQuery(ContactPointAddress.SObjectType, new List<String>(), 'Id', '=');

    System.assertEquals(false, queryString.contains(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME));
  }

  @IsTest
  static void correctlyFormatsAggregateQuery() {
    String countQuery = RollupQueryBuilder.Current.getQuery(Opportunity.SObjectType, new List<String>{ 'count()' }, 'Id', '=');

    Integer countAmount = Database.countQuery(countQuery);

    System.assertEquals(0, countAmount, 'Should make it here because query was formatted correctly');
  }

  @IsTest
  static void doesNotBlowUpOnDeeplyNestedConditionals() {
    String bigWhere = '(((Type = \'Event\' AND Status != \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Letter-Note\' AND Status != \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Meeting\' AND Status != \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Email\' AND Status != \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Call\' AND Status != \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Text\' AND Status = \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Voicemail\' AND Status = \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Letter-Note\' AND Status = \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Event\' AND Status = \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Meeting\' AND Status = \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Email\' AND Status = \'Completed\' AND IsArchived = true) AND WhoId = :recordIds) OR ((Type = \'Call\' AND Status = \'Completed\' AND IsArchived = true) AND WhoId = :recordIds))';

    String queryString = RollupQueryBuilder.Current.getQuery(Task.SObjectType, new List<String>{ 'Id' }, 'Id', '=', bigWhere);

    Set<Id> recordIds = new Set<Id>();
    List<Task> tasks = Database.query(queryString);

    System.assertEquals(true, tasks.isEmpty(), 'Should have made it here and query should have been run');
  }

  @IsTest
  static void properlyFormatsOrWithAndClause() {
    String whereClause = '(StageName = \'one\' AND CloseDate = TODAY) OR (StageName = \'four\' AND CloseDate = TODAY)';

    String actualQuery = RollupQueryBuilder.Current.getQuery(Opportunity.SObjectType, new List<String>{ 'COUNT()' }, 'Id', '!=', whereClause);

    System.assertEquals(0, Database.countQuery(actualQuery), 'Validation that query is syntactically valid');
    System.assertEquals(
      'SELECT count()\nFROM Opportunity\nWHERE Id != :objIds\nAND ((StageName = \'one\' AND CloseDate = TODAY) OR (StageName = \'four\' AND CloseDate = TODAY))',
      actualQuery
    );
  }
}

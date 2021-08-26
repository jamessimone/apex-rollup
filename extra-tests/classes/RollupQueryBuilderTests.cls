@IsTest
private class RollupQueryBuilderTests {
  @IsTest
  static void shouldQueryAllTasks() {
    String queryString = RollupQueryBuilder.Current.getQuery(Task.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    // validate the query
    Set<String> objIds = new Set<String>();
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

    Set<String> objIds = new Set<String>();
    List<SObject> records = Database.query(queryString);

    System.assertEquals(true, queryString.contains('Id'));
    System.assertEquals(true, queryString.contains('AccountId'));
    System.assertEquals(Opportunity.SObjectType, records.getSObjectType());
  }

  @IsTest
  static void shouldNotBlowUpIfPassedInFieldsAreNullOrBlank() {
    String queryString = RollupQueryBuilder.Current.getQuery(Opportunity.SObjectType, new List<String>{ '', null, ' ', 'Id' }, 'AccountId', '=');

    Set<String> objIds = new Set<String>();
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
}

@IsTest
private class RollupQueryBuilderTests {
  @IsTest
  static void shouldQueryAllTasks() {
    String queryString = RollupQueryBuilder.Current.getQuery(Task.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    // validate the query
    Set<String> objIds = new Set<String>();
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('AND IsDeleted = false ALL ROWS'));
  }

  @IsTest
  static void shouldQueryAllEvents() {
    String queryString = RollupQueryBuilder.Current.getQuery(Event.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    Set<String> objIds = new Set<String>();
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('AND IsDeleted = false ALL ROWS'));
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
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('Id'));
    System.assertEquals(true, queryString.contains('AccountId'));
  }

  @IsTest
  static void shouldNotBlowUpIfPassedInFieldsAreNullOrBlank() {
    String queryString = RollupQueryBuilder.Current.getQuery(Opportunity.SObjectType, new List<String>{ '', null, ' ', 'Id' }, 'AccountId', '=');

    Set<String> objIds = new Set<String>();
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('Id'));
  }

  @IsTest
  static void shouldHandleNestedWhereClauses() {
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
    System.assertEquals(true, queryString.contains('What.Type = \'Account\''), queryString);
  }
}

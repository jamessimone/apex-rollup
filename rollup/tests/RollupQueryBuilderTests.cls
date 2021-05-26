@isTest
private class RollupQueryBuilderTests {
  @isTest
  static void shouldQueryAllTasks() {
    String queryString = RollupQueryBuilder.Current.getQuery(Task.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    // validate the query
    Set<String> objIds = new Set<String>();
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('AND IsDeleted = false ALL ROWS'));
  }

  @isTest
  static void shouldQueryAllEvents() {
    String queryString = RollupQueryBuilder.Current.getQuery(Event.SObjectType, new List<String>{ 'Id' }, 'WhatId', '=');

    Set<String> objIds = new Set<String>();
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('AND IsDeleted = false ALL ROWS'));
  }

  @isTest
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

  @isTest
  static void shouldNotBlowUpIfPassedInFieldsAreNullOrBlank() {
    String queryString = RollupQueryBuilder.Current.getQuery(
      Opportunity.SObjectType,
      new List<String>{ '', null, ' ', 'Id'},
      'AccountId',
      '='
    );

    Set<String> objIds = new Set<String>();
    Database.query(queryString);

    System.assertEquals(true, queryString.contains('Id'));
  }
}

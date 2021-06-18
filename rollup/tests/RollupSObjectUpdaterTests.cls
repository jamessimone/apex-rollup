@isTest
private class RollupSObjectUpdaterTests {
  @isTest
  static void shouldAllowDatetimeToBeSavedAsDate() {
    Datetime now = System.now();

    Opportunity opp = new Opportunity();

    new RollupSObjectUpdater(Opportunity.CloseDate).updateField(opp, now);

    System.assertEquals(now.dateGmt(), opp.CloseDate);
  }

  @isTest
  static void shouldRethrowForUnhandledConversion() {
    SObjectException ex;

    try {
      new RollupSObjectUpdater(Opportunity.CloseDate).updateField(new Opportunity(), 1);
    } catch (SObjectException e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
  }
}

@IsTest
private class RollupLimitsTest {
  @IsTest
  static void correctlyReferencesOrgLimits() {
    System.assertEquals(false, new RollupLimits.Tester(RollupControl__mdt.getInstance('Org_Default'), false).hasExceededOrgAsyncLimit());
  }
}

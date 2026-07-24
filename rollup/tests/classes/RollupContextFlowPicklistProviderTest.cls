@IsTest
private class RollupContextFlowPicklistProviderTest {
  @IsTest
  static void returnsCorrectContextDefault() {
    Assert.areEqual('INSERT', new RollupContextFlowPicklistProvider().getDefaultValue().getValue());
  }

  @IsTest
  static void returnsRollupFlowContextssAsValues() {
    Set<String> expected = new Set<String>{ 'INSERT', 'UPDATE', 'UPSERT', 'DELETE', 'REFRESH' };

    Set<String> actual = new Set<String>();
    for (VisualEditor.DataRow row : new RollupContextFlowPicklistProvider().getValues().getDataRows()) {
      actual.add(row.getValue().toString());
      actual.add(row.getLabel().toString());
    }

    Assert.areEqual(expected, actual);
  }
}

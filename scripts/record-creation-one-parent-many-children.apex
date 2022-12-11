String SCRIPT_VAR_1 = 'sForce';
String SCRIPT_VAR_2 = '8000';
String SCRIPT_VAR_3 = '10';
Integer recordCreationCount = Integer.valueOf(SCRIPT_VAR_2);
Integer currentOppCount = [SELECT COUNT() FROM Opportunity WHERE Account.Name = :SCRIPT_VAR_1];
Integer startingIndex = currentOppCount;
Integer offset = startingIndex + recordCreationCount;

String responseStatus = 'PENDING';
if (currentOppCount < recordCreationCount * Integer.valueOf(SCRIPT_VAR_3)) {
  List<Account> matchingAccounts = [SELECT Id FROM Account WHERE Name = :SCRIPT_VAR_1];
  if (matchingAccounts.isEmpty()) {
    matchingAccounts.add(new Account(Name = SCRIPT_VAR_1));
    insert matchingAccounts;
  }

  Id parentId = matchingAccounts.get(0).Id;

  List<Opportunity> opps = new List<Opportunity>();
  for (Integer index = startingIndex; index < offset; index++) {
    Opportunity opp = new Opportunity(StageName = 'Pipeline', CloseDate = System.today(), Name = 'Child ' + index + System.now().getTime(), Amount = index);
    opp.AccountId = parentId;
    opps.add(opp);
  }

  insert opps;
} else {
  System.debug([SELECT AnnualRevenue FROM Account WHERE Name = :SCRIPT_VAR_1]);
  responseStatus = 'COMPLETED';
}
System.debug(responseStatus);

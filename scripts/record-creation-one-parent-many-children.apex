String accountName = 'sForce';
Integer currentOppCount = [SELECT COUNT() FROM Opportunity WHERE Account.Name = :accountName];
Integer recordCreationCount = 8000;
Integer startingIndex = currentOppCount == 0 ? currentOppCount : currentOppCount + 1;
Integer offset = startingIndex + recordCreationCount;

String responseStatus = 'PENDING';
if (currentOppCount < recordCreationCount * 10) {
  List<Account> matchingAccounts = [SELECT Id FROM Account WHERE Name = :accountName];
  if (matchingAccounts.isEmpty()) {
    matchingAccounts.add(new Account(Name = accountName));
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
  responseStatus = 'COMPLETED';
}
System.debug(responseStatus);

public class DealerJourneyAccountNumberBatch implements Database.Batchable<SObject> {
    
    // The 'start' method now uses a more efficient way to check for missing Account Numbers.
    public Database.QueryLocator start(Database.BatchableContext BC) {
        // Step 1: Query Dealer Journey records with a populated Account Number
        return Database.getQueryLocator(
            'SELECT Id, Account_Number__c, Dealer__c, Vendor__c ' +
            'FROM Dealer_Journey__c ' +
            'WHERE Account_Number__c != NULL'
        );
    }

    // The 'execute' method processes each Dealer Journey and creates Account_Number__c records for them
    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        Set<String> accountNumberSet = new Set<String>();
        List<Account_Number__c> newAccountNumbers = new List<Account_Number__c>();

        // Step 2: Query all Account_Number__c records and store their Names in a Set
        for (Account_Number__c acc : [SELECT Name FROM Account_Number__c]) {
            accountNumberSet.add(acc.Name);
        }
        
        // Step 3: Process Dealer Journey records and create missing Account Numbers
        for (Dealer_Journey__c journey : (List<Dealer_Journey__c>) scope) {
            // Check if the Account Number exists in the set of Account Numbers
            if (!accountNumberSet.contains(journey.Account_Number__c)) {
                // Create new Account_Number__c records
                Account_Number__c newAccount = new Account_Number__c(
                    Account_Number__c = journey.Account_Number__c,  // Use the Account Number from the Dealer Journey as the Name
                    Dealer_Journey__c = journey.Id,    // Link back to the Dealer Journey
                    Dealer__c = journey.Dealer__c,     // Link to the Dealer
                    Vendor__c = journey.Vendor__c,		// Link to the Vendor
                    Active__c = true,
                    DNU_Buying__c = 'Direct'
                );
                newAccountNumbers.add(newAccount);
            }
        }

        // Insert the new Account Number records in bulk
        if (!newAccountNumbers.isEmpty()) {
            insert newAccountNumbers;
            System.debug('Created ' + newAccountNumbers.size() + ' missing Account Number records.');
        }
    }

    // The 'finish' method is called after the batch is processed, used for any final operations (logging, notifications, etc.)
    public void finish(Database.BatchableContext BC) {
        System.debug('Batch process completed for missing Account Numbers.');
    }
}
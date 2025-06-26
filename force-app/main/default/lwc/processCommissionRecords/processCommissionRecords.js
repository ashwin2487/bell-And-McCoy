import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import runBatch from '@salesforce/apex/CommissionImportBatchService.runBatch';

export default class ProcessCommissionRecords extends LightningElement {
    @api recordId;
    isLoading = false;

    handleRunBatch() {
        this.isLoading = true;

        runBatch({ importRecordId: this.recordId })
            .then(() => {
                this.showToast('Success', 'Batch started successfully!', 'success');
            })
            .catch(error => {
                const message = error?.body?.message || error?.message || 'Unknown error';
                this.showToast('Error', message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
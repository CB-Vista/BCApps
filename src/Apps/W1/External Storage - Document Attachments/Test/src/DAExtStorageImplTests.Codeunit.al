// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------

namespace Microsoft.ExternalStorage.DocumentAttachments.Test;

using Microsoft.ExternalStorage.DocumentAttachments;
using Microsoft.Foundation.Attachment;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using System.Environment;
using System.ExternalFileStorage;
using System.TestLibraries.ExternalFileStorage;
using System.TestLibraries.Utilities;
using System.Utilities;

codeunit 136820 "DA Ext. Storage Impl. Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions = tabledata "Document Attachment" = rimd,
                  tabledata "Tenant Media" = r,
                  tabledata "DA External Storage Setup" = rimd;

    var
        Any: Codeunit Any;
        FileConnectorMock: Codeunit "File Connector Mock";
        FileScenarioMock: Codeunit "File Scenario Mock";
        Assert: Codeunit "Library Assert";
        CannotRetrieveExternalFileErr: Label 'could not be retrieved from external storage', Locked = true;
        DialogErrorCodeTok: Label 'Dialog', Locked = true;

    #region Successful Operations Tests

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure UploadSucceedsWithValidSetup()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Upload should succeed when feature is enabled and document has content
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeature();

        // [GIVEN] A document attachment with content
        CreateDocumentAttachmentWithContent(DocumentAttachment);

        // [WHEN] Upload is attempted
        Result := DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);

        // [THEN] Upload should succeed
        Assert.IsTrue(Result, 'Upload should succeed with valid setup');

        // [THEN] Document should be marked as stored externally
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        Assert.IsTrue(DocumentAttachment."Stored Externally", 'Document should be marked as stored externally');
        Assert.AreNotEqual('', DocumentAttachment."External File Path", 'External file path should be set');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure UploadSetsCorrectMetadata()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        EnvironmentHash: Text[32];
    begin
        // [SCENARIO] Upload should set all required metadata fields
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeature();

        // [GIVEN] A document attachment with content
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        EnvironmentHash := DAExternalStorageImpl.GetCurrentEnvironmentHash();

        // [WHEN] Upload is performed
        DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);

        // [THEN] All metadata fields should be set correctly
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        Assert.IsTrue(DocumentAttachment."Stored Externally", 'Should be marked as externally stored');
        Assert.AreNotEqual(0DT, DocumentAttachment."External Upload Date", 'Upload date should be set');
        Assert.AreEqual(EnvironmentHash, DocumentAttachment."Source Environment Hash", 'Environment hash should match');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure DeleteFromExternalSucceedsForUploadedFile()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Delete from external should succeed for properly uploaded file
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeatureWithDelete();

        // [GIVEN] A document that has been uploaded to external storage
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();

        // [WHEN] Delete is attempted
        Result := DAExternalStorageImpl.DeleteFromExternalStorage(DocumentAttachment);

        // [THEN] Delete should succeed
        Assert.IsTrue(Result, 'Delete should succeed for uploaded file');

        // [THEN] Document should be marked as not stored externally
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        Assert.IsFalse(DocumentAttachment."Stored Externally", 'Document should not be marked as stored externally');
        Assert.AreEqual('', DocumentAttachment."External File Path", 'External file path should be cleared');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure DeleteFromInternalSucceedsAfterExternalUpload()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Delete from internal should succeed after file is uploaded externally
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeature();

        // [GIVEN] A document that has been uploaded to external storage
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();

        // [WHEN] Delete from internal is attempted
        Result := DAExternalStorageImpl.DeleteFromInternalStorage(DocumentAttachment);

        // [THEN] Delete should succeed
        Assert.IsTrue(Result, 'Delete from internal should succeed');

        // [THEN] Document should be marked as not stored internally
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        Assert.IsFalse(DocumentAttachment."Stored Internally", 'Document should not be marked as stored internally');

        // [THEN] Document should still be marked as stored externally
        Assert.IsTrue(DocumentAttachment."Stored Externally", 'Document should still be marked as stored externally');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure MultipleUploadsCreateUniqueFiles()
    var
        DocumentAttachment1: Record "Document Attachment";
        DocumentAttachment2: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result1: Boolean;
        Result2: Boolean;
    begin
        // [SCENARIO] Multiple uploads should create unique file paths
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeature();

        // [GIVEN] Two document attachments with content
        CreateDocumentAttachmentWithContent(DocumentAttachment1);
        CreateDocumentAttachmentWithContent(DocumentAttachment2);

        // [WHEN] Both are uploaded
        Result1 := DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment1);
        Result2 := DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment2);

        // [THEN] Both uploads should succeed
        Assert.IsTrue(Result1, 'First upload should succeed');
        Assert.IsTrue(Result2, 'Second upload should succeed');

        // [THEN] Each document should have a unique path
        DocumentAttachment1.SetRecFilter();
        DocumentAttachment1.FindFirst();
        DocumentAttachment2.SetRecFilter();
        DocumentAttachment2.FindFirst();
        Assert.AreNotEqual(DocumentAttachment1."External File Path", DocumentAttachment2."External File Path",
            'Each document should have unique external path');
    end;

    #endregion

    #region Failure Condition Tests

    [Test]
    procedure UploadFailsWhenFeatureDisabled()
    var
        DAExternalStorageSetup: Record "DA External Storage Setup";
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Upload should fail when feature is disabled
        Initialize();

        // [GIVEN] Feature is disabled
        if DAExternalStorageSetup.Get() then
            DAExternalStorageSetup.Delete();

        // [GIVEN] A document attachment with content
        CreateDocumentAttachmentWithContent(DocumentAttachment);

        // [WHEN] Upload is attempted
        Result := DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);

        // [THEN] Upload should fail
        Assert.IsFalse(Result, 'Upload should fail when feature is disabled');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure UploadFailsForAlreadyUploadedDocument()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Upload should fail for already uploaded document
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeature();

        // [GIVEN] A document attachment already uploaded
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DocumentAttachment."External File Path" := 'existing/path.txt';
        DocumentAttachment.Modify();

        // [WHEN] Upload is attempted again
        Result := DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);

        // [THEN] Upload should fail
        Assert.IsFalse(Result, 'Upload should fail for already uploaded document');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure UploadFailsWhenNoFileScenarioConfigured()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Upload should fail when no file scenario is configured
        Initialize();
        EnableFeatureOnly();

        // [GIVEN] No file scenario is configured (Initialize already clears all mappings)

        // [GIVEN] A document attachment with content
        CreateDocumentAttachmentWithContent(DocumentAttachment);

        // [WHEN] Upload is attempted
        Result := DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);

        // [THEN] Upload should fail
        Assert.IsFalse(Result, 'Upload should fail when no file scenario is configured');
    end;

    [Test]
    procedure DeleteFailsWhenFeatureDisabled()
    var
        DAExternalStorageSetup: Record "DA External Storage Setup";
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Delete should fail when feature is disabled
        Initialize();

        // [GIVEN] Feature is disabled
        if DAExternalStorageSetup.Get() then
            DAExternalStorageSetup.Delete();

        // [GIVEN] A document attachment marked as externally stored
        CreateExternallyStoredDocument(DocumentAttachment);

        // [WHEN] Delete is attempted
        Result := DAExternalStorageImpl.DeleteFromExternalStorage(DocumentAttachment);

        // [THEN] Delete should fail
        Assert.IsFalse(Result, 'Delete should fail when feature is disabled');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure DeleteRemovesLastReferenceWhenSkipDeleteOnCopyIsSet()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
        ExternalFilePath: Text;
    begin
        // [SCENARIO] A legacy copy flag cannot prevent explicit deletion of the last external reference
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeatureWithDelete();

        // [GIVEN] A document attachment with Skip Delete On Copy
        CreateExternallyStoredDocument(DocumentAttachment);
        DocumentAttachment."Skip Delete On Copy" := true;
        DocumentAttachment.Modify();
        ExternalFilePath := DocumentAttachment."External File Path";

        // [WHEN] Delete is attempted
        Result := DAExternalStorageImpl.DeleteFromExternalStorage(DocumentAttachment);

        // [THEN] The last external reference is removed despite the legacy flag
        Assert.IsTrue(Result, 'Deleting the last external reference should succeed despite the legacy copy flag');
        Assert.AreEqual(ExternalFilePath, FileConnectorMock.GetLastDeletedPath(), 'The last reference should delete the external file');

        // [THEN] External metadata is cleared
        AssertExternalMetadataCleared(DocumentAttachment);
    end;

    [Test]
    procedure DeleteFromInternalStorageSucceeds()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Delete from internal storage should succeed for externally stored docs
        Initialize();

        // [GIVEN] A document attachment with content and marked as externally stored
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DocumentAttachment."Stored Externally" := true;
        DocumentAttachment.Modify();

        // [WHEN] Delete from internal is attempted
        Result := DAExternalStorageImpl.DeleteFromInternalStorage(DocumentAttachment);

        // [THEN] Delete should succeed
        Assert.IsTrue(Result, 'Delete from internal should succeed');

        // [THEN] Document should be marked as not stored internally
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        Assert.IsFalse(DocumentAttachment."Stored Internally", 'Document should not be marked as stored internally');
    end;

    [Test]
    procedure DeleteFromInternalFailsForNonExternalDocument()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Delete from internal should fail for non-external document
        Initialize();

        // [GIVEN] A document attachment not stored externally
        CreateDocumentAttachmentWithContent(DocumentAttachment);

        // [WHEN] Delete from internal is attempted
        Result := DAExternalStorageImpl.DeleteFromInternalStorage(DocumentAttachment);

        // [THEN] Delete should fail
        Assert.IsFalse(Result, 'Delete from internal should fail for non-external document');
    end;

    #endregion

    #region OnAfterDelete Subscriber Tests

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure RecordDeleteRemovesBlobFromExternalStorage()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ExternalFilePath: Text;
    begin
        // [SCENARIO] Deleting a Document Attachment row must delete its blob via the OnAfterDelete subscriber.
        // Regression test for the bug where the subscriber called DeleteFromExternalStorage(Rec), which
        // started with Rec.Find() and exited because the row was already gone, leaving the blob orphaned.
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeatureWithDelete();

        // [GIVEN] A document attachment that has been uploaded to external storage
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        ExternalFilePath := DocumentAttachment."External File Path";
        Assert.AreNotEqual('', ExternalFilePath, 'Precondition: upload should set the External File Path');

        // [WHEN] The Document Attachment row is deleted (fires OnAfterDeleteEvent)
        DocumentAttachment.Delete(true);

        // [THEN] The subscriber invoked DeleteFile against the external connector with the stored path
        Assert.AreEqual(ExternalFilePath, FileConnectorMock.GetLastDeletedPath(),
            'External connector DeleteFile should be invoked with the stored External File Path when the attachment row is deleted');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure RecordDeleteRemovesLastBlobWhenSkipDeleteOnCopyIsSet()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ExternalFilePath: Text;
    begin
        // [SCENARIO] A legacy copy flag cannot prevent record deletion from removing an unshared blob
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeatureWithDelete();

        // [GIVEN] An externally-stored attachment flagged as a copy
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        DocumentAttachment."Skip Delete On Copy" := true;
        DocumentAttachment.Modify();
        ExternalFilePath := DocumentAttachment."External File Path";

        // [WHEN] The row is deleted
        DocumentAttachment.Delete(true);

        // [THEN] The subscriber deletes the last external reference despite the legacy flag
        Assert.AreEqual(ExternalFilePath, FileConnectorMock.GetLastDeletedPath(),
            'The last external reference should be deleted even when Skip Delete On Copy is set');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure RecordDeleteKeepsBlobWhenFileIsFromAnotherEnvironment()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ExternalFilePath: Text;
    begin
        // [SCENARIO] Files owned by another environment or company must not be deleted
        // when the local attachment row is removed - the owning environment is responsible
        // for the blob's lifecycle.
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeatureWithDelete();

        // [GIVEN] An externally-stored attachment carrying a foreign source environment hash
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        DocumentAttachment."Source Environment Hash" := 'DIFFERENTHASH123';
        DocumentAttachment.Modify();
        ExternalFilePath := DocumentAttachment."External File Path";

        // [WHEN] The row is deleted
        DocumentAttachment.Delete(true);

        // [THEN] The subscriber must NOT invoke DeleteFile for this path
        Assert.AreNotEqual(ExternalFilePath, FileConnectorMock.GetLastDeletedPath(),
            'External connector DeleteFile should not be invoked when the file belongs to another environment or company');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure RecordDeleteKeepsBlobWhenDeleteFromExternalStorageDisabled()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ExternalFilePath: Text;
    begin
        // [SCENARIO] When the user opted out of automatic deletion, the blob must stay even if the row is deleted.
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeature(); // "Delete from External Storage" = false

        // [GIVEN] An uploaded externally-stored attachment
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment);
        DocumentAttachment.SetRecFilter();
        DocumentAttachment.FindFirst();
        ExternalFilePath := DocumentAttachment."External File Path";

        // [WHEN] The row is deleted
        DocumentAttachment.Delete(true);

        // [THEN] The subscriber must NOT invoke DeleteFile when the feature setting opts out
        Assert.AreNotEqual(ExternalFilePath, FileConnectorMock.GetLastDeletedPath(),
            'External connector DeleteFile should not be invoked when Delete from External Storage is disabled');
    end;

    #endregion

    #region Shared External File Tests

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure QuoteToOrderCopyKeepsHeaderAndLineFilesAfterSourceCleanup()
    begin
        VerifyPurchaseCopyDeletionOrder(false, true, true);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure QuoteToOrderCopyKeepsHeaderAndLineFilesAfterDestinationCleanup()
    begin
        VerifyPurchaseCopyDeletionOrder(false, false, true);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure PostedInvoiceCopyKeepsHeaderAndLineFilesAfterSourceCleanup()
    begin
        VerifyPurchaseCopyDeletionOrder(true, true, true);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure PostedInvoiceCopyKeepsHeaderAndLineFilesAfterDestinationCleanup()
    begin
        VerifyPurchaseCopyDeletionOrder(true, false, true);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure QuoteToOrderSourceCleanupKeepsFilesWhenAutomaticDeletionDisabled()
    begin
        VerifyPurchaseCopyDeletionOrder(false, true, false);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure QuoteToOrderDestinationCleanupKeepsFilesWhenAutomaticDeletionDisabled()
    begin
        VerifyPurchaseCopyDeletionOrder(false, false, false);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure PostedInvoiceSourceCleanupKeepsFilesWhenAutomaticDeletionDisabled()
    begin
        VerifyPurchaseCopyDeletionOrder(true, true, false);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure PostedInvoiceDestinationCleanupKeepsFilesWhenAutomaticDeletionDisabled()
    begin
        VerifyPurchaseCopyDeletionOrder(true, false, false);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure MultipleCopyDestinationsKeepFileUntilLegacyFlaggedLastCopyIsDeleted()
    var
        SourceHeader: Record "Purchase Header";
        SourceLine: Record "Purchase Line";
        FirstHeader: Record "Purchase Header";
        FirstLine: Record "Purchase Line";
        SecondHeader: Record "Purchase Header";
        SecondLine: Record "Purchase Line";
        SourceAttachment: Record "Document Attachment";
        FirstAttachment: Record "Document Attachment";
        SecondAttachment: Record "Document Attachment";
        DocumentAttachmentMgmt: Codeunit "Document Attachment Mgmt";
        ExternalFilePath: Text;
    begin
        // [SCENARIO] Multiple real copy destinations share one file, including legacy flagged copies
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeatureWithDelete();

        // [GIVEN] A quote attachment copied to two orders
        CreatePurchaseDocument(SourceHeader, SourceLine, SourceHeader."Document Type"::Quote);
        CreatePurchaseAttachment(SourceAttachment, SourceHeader, 0);
        ExternalFilePath := SourceAttachment."External File Path";
        CreatePurchaseDocument(FirstHeader, FirstLine, FirstHeader."Document Type"::Order);
        CreatePurchaseDocument(SecondHeader, SecondLine, SecondHeader."Document Type"::Order);
        DocumentAttachmentMgmt.CopyAttachments(SourceHeader, FirstHeader);
        DocumentAttachmentMgmt.CopyAttachments(SourceHeader, SecondHeader);
        GetCopiedAttachment(FirstAttachment, SourceAttachment, Database::"Purchase Header", FirstHeader."No.", Enum::"Attachment Document Type"::Order);
        GetCopiedAttachment(SecondAttachment, SourceAttachment, Database::"Purchase Header", SecondHeader."No.", Enum::"Attachment Document Type"::Order);
        AssertCopiedExternalReference(SourceAttachment, FirstAttachment);
        AssertCopiedExternalReference(SourceAttachment, SecondAttachment);
        SecondAttachment."Skip Delete On Copy" := true;
        SecondAttachment.Modify();

        // [WHEN] The source and then the first destination are cleaned up
        DeletePurchaseDocument(SourceHeader, SourceLine);
        Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Source cleanup must keep files referenced by both destinations');
        DeletePurchaseDocument(FirstHeader, FirstLine);

        // [THEN] The last destination still owns the shared file
        Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Deleting one destination must keep the remaining reference');
        RefreshAttachment(SecondAttachment);
        Assert.AreEqual(ExternalFilePath, SecondAttachment."External File Path", 'The surviving copy must retain its external path');

        // [WHEN] The final, legacy flagged destination is cleaned up
        DeletePurchaseDocument(SecondHeader, SecondLine);

        // [THEN] Its legacy flag does not orphan the external file
        Assert.AreEqual(ExternalFilePath, FileConnectorMock.GetLastDeletedPath(), 'The last destination must delete the file despite its legacy flag');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure DifferentExternalPathsHaveIndependentLifetimes()
    var
        FirstAttachment: Record "Document Attachment";
        CopiedAttachment: Record "Document Attachment";
        OtherAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        SharedPath: Text;
        OtherPath: Text;
    begin
        // [SCENARIO] An unrelated external path cannot block deletion or be deleted with a shared file
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeatureWithDelete();

        // [GIVEN] Two references to one external path and an attachment with a different path
        CreateDocumentAttachmentWithContent(FirstAttachment);
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(FirstAttachment), 'First upload should succeed');
        CreateCopyOfDocumentAttachment(FirstAttachment, CopiedAttachment);
        CreateDocumentAttachmentWithContent(OtherAttachment);
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(OtherAttachment), 'Other upload should succeed');
        SharedPath := FirstAttachment."External File Path";
        OtherPath := OtherAttachment."External File Path";
        Assert.AreNotEqual(SharedPath, OtherPath, 'Precondition: unrelated files must have different paths');

        // [WHEN] The unrelated attachment is deleted while the shared references survive
        OtherAttachment.Delete(true);

        // [THEN] Only its own file is deleted
        Assert.AreEqual(OtherPath, FileConnectorMock.GetLastDeletedPath(), 'A different path must not prevent deleting the unrelated file');

        // [WHEN] One shared reference is deleted
        FirstAttachment.Delete(true);

        // [THEN] No additional file is deleted
        Assert.AreEqual(OtherPath, FileConnectorMock.GetLastDeletedPath(), 'The shared path must remain until its final reference is deleted');
        RefreshAttachment(CopiedAttachment);
        Assert.AreEqual(SharedPath, CopiedAttachment."External File Path", 'The shared copy must retain its path');

        // [WHEN] The last shared reference is deleted
        CopiedAttachment.Delete(true);

        // [THEN] Its own file is deleted
        Assert.AreEqual(SharedPath, FileConnectorMock.GetLastDeletedPath(), 'The final shared reference must delete its file');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure SharedRecordDeletionKeepsFileWhenAutomaticDeletionDisabled()
    var
        SourceAttachment: Record "Document Attachment";
        CopiedAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
    begin
        // [SCENARIO] Automatic deletion disabled keeps the file even after all shared rows are deleted
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeature();

        // [GIVEN] Two attachments sharing an uploaded file
        CreateDocumentAttachmentWithContent(SourceAttachment);
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(SourceAttachment), 'Upload should succeed');
        CreateCopyOfDocumentAttachment(SourceAttachment, CopiedAttachment);

        // [WHEN] Both references are deleted
        SourceAttachment.Delete(true);
        Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'The first deleted reference must keep the external file');
        CopiedAttachment.Delete(true);

        // [THEN] The setting prevents deleting even the last external reference
        Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Automatic deletion disabled must preserve the file after the last record is deleted');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure ExplicitRemoveOfSharedFileWithAutomaticDeletionEnabled()
    begin
        VerifyExplicitRemoveOfSharedFile(true);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure ExplicitRemoveOfSharedFileWithAutomaticDeletionDisabled()
    begin
        VerifyExplicitRemoveOfSharedFile(false);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure ExplicitRemoveKeepsFileOwnedByAnotherEnvironment()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
    begin
        // [SCENARIO] Explicit removal releases a foreign reference without deleting another environment's file
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeatureWithDelete();

        // [GIVEN] A single external reference owned by another environment
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment), 'Upload should succeed');
        DocumentAttachment."Source Environment Hash" := 'DIFFERENTHASH123';
        DocumentAttachment.Modify();

        // [WHEN] The last local external reference is explicitly removed
        Assert.IsTrue(DAExternalStorageImpl.DeleteFromExternalStorage(DocumentAttachment), 'Removing a foreign external reference should succeed');

        // [THEN] Its local metadata is cleared without deleting the foreign file
        AssertExternalMetadataCleared(DocumentAttachment);
        Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Ownership must prevent physical deletion even for the last local reference');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler,SyncMessageHandler')]
    procedure SyncMoveOfSharedFileWithAutomaticDeletionEnabled()
    begin
        VerifySyncMoveOfSharedFile(true);
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler,SyncMessageHandler')]
    procedure SyncMoveOfSharedFileWithAutomaticDeletionDisabled()
    begin
        VerifySyncMoveOfSharedFile(false);
    end;

    #endregion

    #region MIME Type Tests

    [Test]
    procedure FileExtensionToContentMimeTypeReturnsPdfForPdf()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ContentType: Text[100];
    begin
        // [SCENARIO] Should return correct MIME type for PDF
        Initialize();

        // [GIVEN] A document attachment with PDF extension
        DocumentAttachment.Init();
        DocumentAttachment."File Extension" := 'pdf';

        // [WHEN] Content type is requested
        DAExternalStorageImpl.FileExtensionToContentMimeType(DocumentAttachment, ContentType);

        // [THEN] Should return PDF MIME type
        Assert.AreEqual('application/pdf', ContentType, 'Should return PDF MIME type');
    end;

    [Test]
    procedure FileExtensionToContentMimeTypeReturnsJpegForJpg()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ContentType: Text[100];
    begin
        // [SCENARIO] Should return correct MIME type for JPG
        Initialize();

        // [GIVEN] A document attachment with JPG extension
        DocumentAttachment.Init();
        DocumentAttachment."File Extension" := 'jpg';

        // [WHEN] Content type is requested
        DAExternalStorageImpl.FileExtensionToContentMimeType(DocumentAttachment, ContentType);

        // [THEN] Should return JPEG MIME type
        Assert.AreEqual('image/jpeg', ContentType, 'Should return JPEG MIME type');
    end;

    [Test]
    procedure FileExtensionToContentMimeTypeReturnsOctetStreamForUnknown()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ContentType: Text[100];
    begin
        // [SCENARIO] Should return octet-stream for unknown extensions
        Initialize();

        // [GIVEN] A document attachment with unknown extension
        DocumentAttachment.Init();
        DocumentAttachment."File Extension" := 'xyz123';

        // [WHEN] Content type is requested
        DAExternalStorageImpl.FileExtensionToContentMimeType(DocumentAttachment, ContentType);

        // [THEN] Should return octet-stream
        Assert.AreEqual('application/octet-stream', ContentType, 'Should return octet-stream for unknown extension');
    end;

    [Test]
    procedure FileExtensionToContentMimeTypeReturnsDocxMimeType()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ContentType: Text[100];
    begin
        // [SCENARIO] Should return correct MIME type for DOCX
        Initialize();

        // [GIVEN] A document attachment with DOCX extension
        DocumentAttachment.Init();
        DocumentAttachment."File Extension" := 'docx';

        // [WHEN] Content type is requested
        DAExternalStorageImpl.FileExtensionToContentMimeType(DocumentAttachment, ContentType);

        // [THEN] Should return DOCX MIME type
        Assert.AreEqual('application/vnd.openxmlformats-officedocument.wordprocessingml.document', ContentType,
            'Should return DOCX MIME type');
    end;

    [Test]
    procedure FileExtensionToContentMimeTypeReturnsXlsxMimeType()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ContentType: Text[100];
    begin
        // [SCENARIO] Should return correct MIME type for XLSX
        Initialize();

        // [GIVEN] A document attachment with XLSX extension
        DocumentAttachment.Init();
        DocumentAttachment."File Extension" := 'xlsx';

        // [WHEN] Content type is requested
        DAExternalStorageImpl.FileExtensionToContentMimeType(DocumentAttachment, ContentType);

        // [THEN] Should return XLSX MIME type
        Assert.AreEqual('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', ContentType,
            'Should return XLSX MIME type');
    end;

    #endregion

    #region Environment Hash Tests

    [Test]
    procedure GetCurrentEnvironmentHashReturnsConsistentValue()
    var
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Hash1: Text[32];
        Hash2: Text[32];
    begin
        // [SCENARIO] Environment hash should be consistent
        Initialize();

        // [WHEN] Hash is generated twice
        Hash1 := DAExternalStorageImpl.GetCurrentEnvironmentHash();
        Hash2 := DAExternalStorageImpl.GetCurrentEnvironmentHash();

        // [THEN] Both hashes should be equal
        Assert.AreEqual(Hash1, Hash2, 'Environment hash should be consistent');

        // [THEN] Hash should not be empty
        Assert.AreNotEqual('', Hash1, 'Hash should not be empty');
    end;

    [Test]
    procedure IsFileFromAnotherEnvironmentReturnsFalseForCurrentEnvironment()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Should return false for files from current environment
        Initialize();

        // [GIVEN] A document with current environment hash
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DocumentAttachment."Source Environment Hash" := DAExternalStorageImpl.GetCurrentEnvironmentHash();
        DocumentAttachment.Modify();

        // [WHEN] Checking if from another environment
        Result := DAExternalStorageImpl.IsFileFromAnotherEnvironmentOrCompany(DocumentAttachment);

        // [THEN] Should return false
        Assert.IsFalse(Result, 'Should return false for current environment');
    end;

    [Test]
    procedure IsFileFromAnotherEnvironmentReturnsTrueForDifferentEnvironment()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Should return true for files from different environment
        Initialize();

        // [GIVEN] A document with different environment hash
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DocumentAttachment."Source Environment Hash" := 'DIFFERENTHASH123';
        DocumentAttachment.Modify();

        // [WHEN] Checking if from another environment
        Result := DAExternalStorageImpl.IsFileFromAnotherEnvironmentOrCompany(DocumentAttachment);

        // [THEN] Should return true
        Assert.IsTrue(Result, 'Should return true for different environment');
    end;

    [Test]
    procedure IsFileFromAnotherEnvironmentReturnsFalseForEmptyHash()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Should return false when source hash is empty
        Initialize();

        // [GIVEN] A document without source environment hash
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DocumentAttachment."Source Environment Hash" := '';
        DocumentAttachment.Modify();

        // [WHEN] Checking if from another environment
        Result := DAExternalStorageImpl.IsFileFromAnotherEnvironmentOrCompany(DocumentAttachment);

        // [THEN] Should return false (assumes current environment)
        Assert.IsFalse(Result, 'Should return false when hash is empty');
    end;

    #endregion

    #region External File Status Tests

    [Test]
    procedure IsFileUploadedExternallyAndDeletedInternallyChecksAllConditions()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Should correctly identify externally stored and internally deleted files
        Initialize();

        // [GIVEN] A document that is externally stored but not internally stored
        CreateExternallyStoredOnlyDocument(DocumentAttachment);

        // [WHEN] Checking if uploaded externally and deleted internally
        Result := DAExternalStorageImpl.IsFileUploadedToExternalStorageAndDeletedInternally(DocumentAttachment);

        // [THEN] Should return true
        Assert.IsTrue(Result, 'Should return true for externally stored and internally deleted file');
    end;

    [Test]
    procedure HasContentUsesExternalStorageMetadataWithFileAccount()
    var
        DocumentAttachment: Record "Document Attachment";
    begin
        // [SCENARIO] Checking attachment content should not contact external storage
        Initialize();
        SetupFileScenarioWithTestConnector();

        // [GIVEN] An externally stored attachment with a configured file account
        CreateExternallyStoredOnlyDocument(DocumentAttachment);

        // [WHEN] Checking if the attachment has content
        // [THEN] The external storage metadata indicates content is available
        Assert.IsTrue(DocumentAttachment.HasContent(), 'Externally stored attachment should report content from its metadata');
        Assert.AreEqual(0, FileConnectorMock.GetFileExistsCallCount(), 'Checking content should not call the external file connector');
    end;

    [Test]
    procedure HasContentUsesExternalStorageMetadataWithoutFileAccount()
    var
        DocumentAttachment: Record "Document Attachment";
    begin
        // [SCENARIO] External attachment metadata remains available when the file account mapping is missing
        Initialize();

        // [GIVEN] An externally stored attachment without a configured file account
        CreateExternallyStoredOnlyDocument(DocumentAttachment);

        // [WHEN] Checking if the attachment has content
        // [THEN] The external storage metadata indicates content is available
        Assert.IsTrue(DocumentAttachment.HasContent(), 'Externally stored attachment should report content without a file account mapping');
    end;

    [Test]
    procedure HasContentUsesInternalStorageWithoutExternalCall()
    var
        DocumentAttachment: Record "Document Attachment";
    begin
        // [SCENARIO] Internally stored attachments continue to use the document reference
        Initialize();
        SetupFileScenarioWithTestConnector();

        // [GIVEN] An internally stored attachment
        CreateDocumentAttachmentWithContent(DocumentAttachment);

        // [WHEN] Checking if the attachment has content
        // [THEN] The internal content is available without calling external storage
        Assert.IsTrue(DocumentAttachment.HasContent(), 'Internally stored attachment should report content from its document reference');
        Assert.AreEqual(0, FileConnectorMock.GetFileExistsCallCount(), 'Internal content checks should not call the external file connector');
    end;

    [Test]
    procedure ExportToStreamErrorsWhenExternalFileCannotBeRetrieved()
    var
        DocumentAttachment: Record "Document Attachment";
        TempBlob: Codeunit "Temp Blob";
        AttachmentOutStream: OutStream;
    begin
        // [SCENARIO] Exporting an unavailable external attachment surfaces an error
        Initialize();
        SetupFileScenarioWithTestConnector();
        FileConnectorMock.SetFailOnGetFile(true);

        // [GIVEN] An externally stored attachment that the connector cannot retrieve
        CreateExternallyStoredOnlyDocument(DocumentAttachment);
        TempBlob.CreateOutStream(AttachmentOutStream);

        // [WHEN] Exporting the attachment to a stream
        asserterror DocumentAttachment.ExportToStream(AttachmentOutStream);

        // [THEN] The retrieval failure is surfaced
        Assert.ExpectedErrorCode(DialogErrorCodeTok);
        Assert.ExpectedError(CannotRetrieveExternalFileErr);
    end;

    [Test]
    procedure GetAsTempBlobErrorsWhenExternalFileCannotBeRetrieved()
    var
        DocumentAttachment: Record "Document Attachment";
        TempBlob: Codeunit "Temp Blob";
    begin
        // [SCENARIO] Previewing an unavailable external attachment surfaces an error
        Initialize();
        SetupFileScenarioWithTestConnector();
        FileConnectorMock.SetFailOnGetFile(true);

        // [GIVEN] An externally stored attachment that the connector cannot retrieve
        CreateExternallyStoredOnlyDocument(DocumentAttachment);

        // [WHEN] Loading the attachment into a temporary blob
        asserterror DocumentAttachment.GetAsTempBlob(TempBlob);

        // [THEN] The retrieval failure is surfaced
        Assert.ExpectedErrorCode(DialogErrorCodeTok);
        Assert.ExpectedError(CannotRetrieveExternalFileErr);
    end;

    [Test]
    procedure GetAsTempBlobErrorsWithoutFileAccount()
    var
        DocumentAttachment: Record "Document Attachment";
        TempBlob: Codeunit "Temp Blob";
    begin
        // [SCENARIO] Previewing an external attachment without a file account mapping surfaces an error
        Initialize();

        // [GIVEN] An externally stored attachment without a configured file account
        CreateExternallyStoredOnlyDocument(DocumentAttachment);

        // [WHEN] Loading the attachment into a temporary blob
        asserterror DocumentAttachment.GetAsTempBlob(TempBlob);

        // [THEN] The missing configuration is surfaced
        Assert.ExpectedErrorCode(DialogErrorCodeTok);
        Assert.ExpectedError(CannotRetrieveExternalFileErr);
    end;

    [Test]
    procedure ExportToStreamErrorsWithoutFileAccount()
    var
        DocumentAttachment: Record "Document Attachment";
        TempBlob: Codeunit "Temp Blob";
        AttachmentOutStream: OutStream;
    begin
        // [SCENARIO] Exporting an external attachment without a file account mapping surfaces an error
        Initialize();

        // [GIVEN] An externally stored attachment without a configured file account
        CreateExternallyStoredOnlyDocument(DocumentAttachment);
        TempBlob.CreateOutStream(AttachmentOutStream);

        // [WHEN] Exporting the attachment to a stream
        asserterror DocumentAttachment.ExportToStream(AttachmentOutStream);

        // [THEN] The missing configuration is surfaced
        Assert.ExpectedErrorCode(DialogErrorCodeTok);
        Assert.ExpectedError(CannotRetrieveExternalFileErr);
    end;

    [Test]
    procedure IsFileUploadedExternallyReturnsFalseWhenStoredInternally()
    var
        DocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        Result: Boolean;
    begin
        // [SCENARIO] Should return false when file is still stored internally
        Initialize();

        // [GIVEN] A document that is externally stored AND internally stored
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DocumentAttachment."Stored Externally" := true;
        DocumentAttachment."External File Path" := 'test/path/file.txt';
        DocumentAttachment.Modify();

        // [WHEN] Checking if uploaded externally and deleted internally
        Result := DAExternalStorageImpl.IsFileUploadedToExternalStorageAndDeletedInternally(DocumentAttachment);

        // [THEN] Should return false (still has internal copy)
        Assert.IsFalse(Result, 'Should return false when file is still stored internally');
    end;

    #endregion

    #region Shared Tenant Media Tests

    [Test]
    procedure DeleteFromInternalKeepsMediaSharedWithCopiedAttachment()
    var
        DocumentAttachment: Record "Document Attachment";
        CopiedDocumentAttachment: Record "Document Attachment";
        TenantMedia: Record "Tenant Media";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        SharedMediaId: Guid;
    begin
        // [SCENARIO] Deleting an attachment from internal storage must not remove the Tenant Media
        // while a copied attachment still references it.
        Initialize();

        // [GIVEN] An attachment with content that has been copied to another document
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        SharedMediaId := DocumentAttachment."Document Reference ID".MediaId();
        CreateCopyOfDocumentAttachment(DocumentAttachment, CopiedDocumentAttachment);

        // [GIVEN] The original attachment is stored externally
        DocumentAttachment."Stored Externally" := true;
        DocumentAttachment.Modify();

        // [WHEN] The original is deleted from internal storage
        Assert.IsTrue(DAExternalStorageImpl.DeleteFromInternalStorage(DocumentAttachment), 'Delete from internal should succeed');

        // [THEN] The shared Tenant Media is kept
        Assert.IsTrue(TenantMedia.Get(SharedMediaId), 'Shared Tenant Media should not be deleted');

        // [THEN] The copied attachment still has its content
        RefreshAttachment(CopiedDocumentAttachment);
        Assert.IsTrue(CopiedDocumentAttachment."Document Reference ID".HasValue(), 'Copied attachment should still have content');

        // [THEN] The original has released its own reference
        RefreshAttachment(DocumentAttachment);
        Assert.IsFalse(DocumentAttachment."Document Reference ID".HasValue(), 'Original attachment should have released its media reference');
        Assert.IsFalse(DocumentAttachment."Stored Internally", 'Original should not be marked as stored internally');
    end;

    [Test]
    procedure DeleteFromInternalRemovesMediaWhenNotShared()
    var
        DocumentAttachment: Record "Document Attachment";
        TenantMedia: Record "Tenant Media";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        MediaId: Guid;
    begin
        // [SCENARIO] Database space is still reclaimed when the attachment is the only owner
        Initialize();

        // [GIVEN] An attachment with content that is not shared and is stored externally
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        MediaId := DocumentAttachment."Document Reference ID".MediaId();
        DocumentAttachment."Stored Externally" := true;
        DocumentAttachment.Modify();

        // [WHEN] It is deleted from internal storage
        Assert.IsTrue(DAExternalStorageImpl.DeleteFromInternalStorage(DocumentAttachment), 'Delete from internal should succeed');

        // [THEN] The Tenant Media is removed
        Assert.IsFalse(TenantMedia.Get(MediaId), 'Tenant Media should be deleted when no other attachment references it');
    end;

    [Test]
    [HandlerFunctions('ConfirmYesHandler')]
    procedure UploadSucceedsForCopiedAttachmentAfterSourceIsMigrated()
    var
        DocumentAttachment: Record "Document Attachment";
        CopiedDocumentAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
    begin
        // [SCENARIO] A copied attachment can still be migrated after the attachment it was copied from
        // has been moved to external storage. The shared Tenant Media used to be deleted together with
        // the source, which left the copy with neither internal content nor an external file.
        Initialize();
        SetupFileScenarioWithTestConnector();
        EnableFeature();

        // [GIVEN] An attachment that has been copied to another document
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        CreateCopyOfDocumentAttachment(DocumentAttachment, CopiedDocumentAttachment);

        // [GIVEN] The source attachment has been moved to external storage
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment), 'Upload of the source should succeed');
        RefreshAttachment(DocumentAttachment);
        Assert.IsTrue(DAExternalStorageImpl.DeleteFromInternalStorage(DocumentAttachment), 'Delete from internal should succeed for the source');

        // [WHEN] The copied attachment is uploaded
        RefreshAttachment(CopiedDocumentAttachment);
        Assert.IsTrue(CopiedDocumentAttachment."Document Reference ID".HasValue(), 'Copied attachment should still have content');

        // [THEN] The upload succeeds
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(CopiedDocumentAttachment), 'Upload of the copied attachment should succeed');

        // [THEN] Both attachments are stored externally, each in its own file
        RefreshAttachment(DocumentAttachment);
        RefreshAttachment(CopiedDocumentAttachment);
        Assert.IsTrue(CopiedDocumentAttachment."Stored Externally", 'Copied attachment should be marked as stored externally');
        Assert.AreNotEqual(DocumentAttachment."External File Path", CopiedDocumentAttachment."External File Path", 'Each attachment should have its own external file');
    end;

    #endregion

    #region Helper Functions

    local procedure VerifyPurchaseCopyDeletionOrder(PostedCopy: Boolean; SourceFirst: Boolean; AutomaticDeletion: Boolean)
    var
        SourceHeader: Record "Purchase Header";
        SourceLine: Record "Purchase Line";
        DestinationHeader: Record "Purchase Header";
        DestinationLine: Record "Purchase Line";
        PurchInvHeader: Record "Purch. Inv. Header";
        PurchInvLine: Record "Purch. Inv. Line";
        SourceHeaderAttachment: Record "Document Attachment";
        SourceLineAttachment: Record "Document Attachment";
        DestinationHeaderAttachment: Record "Document Attachment";
        DestinationLineAttachment: Record "Document Attachment";
        RemainingHeaderAttachment: Record "Document Attachment";
        RemainingLineAttachment: Record "Document Attachment";
        DeletedAttachment: Record "Document Attachment";
        DocumentAttachmentMgmt: Codeunit "Document Attachment Mgmt";
        FromRecRef: RecordRef;
        ToRecRef: RecordRef;
    begin
        // [SCENARIO] Real purchase attachment copy APIs preserve header and line files through document cleanup in either order
        Initialize();
        SetupFileScenarioWithTestConnector();
        if AutomaticDeletion then
            EnableFeatureWithDelete()
        else
            EnableFeature();

        // [GIVEN] A purchase document with uploaded header and line attachments
        if PostedCopy then
            CreatePurchaseDocument(SourceHeader, SourceLine, SourceHeader."Document Type"::Order)
        else
            CreatePurchaseDocument(SourceHeader, SourceLine, SourceHeader."Document Type"::Quote);
        CreatePurchaseAttachment(SourceHeaderAttachment, SourceHeader, 0);
        CreatePurchaseAttachment(SourceLineAttachment, SourceHeader, SourceLine."Line No.");

        // [GIVEN] Copies created by the actual quote-to-order or posted-document attachment APIs, without financial posting
        if PostedCopy then begin
            PurchInvHeader.Init();
            PurchInvHeader."No." := CopyStr(Any.AlphanumericText(20), 1, MaxStrLen(PurchInvHeader."No."));
            PurchInvHeader.Insert(false);
            PurchInvLine.Init();
            PurchInvLine."Document No." := PurchInvHeader."No.";
            PurchInvLine."Line No." := SourceLine."Line No.";
            PurchInvLine.Insert(false);
            FromRecRef.GetTable(SourceHeader);
            ToRecRef.GetTable(PurchInvHeader);
            DocumentAttachmentMgmt.CopyAttachmentsForPostedDocs(FromRecRef, ToRecRef);
            GetCopiedAttachment(DestinationHeaderAttachment, SourceHeaderAttachment, Database::"Purch. Inv. Header", PurchInvHeader."No.", Enum::"Attachment Document Type"::Invoice);
            GetCopiedAttachment(DestinationLineAttachment, SourceLineAttachment, Database::"Purch. Inv. Line", PurchInvHeader."No.", Enum::"Attachment Document Type"::Invoice);
        end else begin
            CreatePurchaseDocument(DestinationHeader, DestinationLine, DestinationHeader."Document Type"::Order);
            DocumentAttachmentMgmt.CopyAttachments(SourceHeader, DestinationHeader);
            DocumentAttachmentMgmt.CopyAttachments(SourceLine, DestinationLine);
            GetCopiedAttachment(DestinationHeaderAttachment, SourceHeaderAttachment, Database::"Purchase Header", DestinationHeader."No.", Enum::"Attachment Document Type"::Order);
            GetCopiedAttachment(DestinationLineAttachment, SourceLineAttachment, Database::"Purchase Line", DestinationHeader."No.", Enum::"Attachment Document Type"::Order);
        end;
        AssertCopiedExternalReference(SourceHeaderAttachment, DestinationHeaderAttachment);
        AssertCopiedExternalReference(SourceLineAttachment, DestinationLineAttachment);

        // [WHEN] Either the source or destination document is deleted through its attachment cleanup subscribers
        if SourceFirst then begin
            DeletePurchaseDocument(SourceHeader, SourceLine);
            Assert.IsFalse(DeletedAttachment.GetBySystemId(SourceHeaderAttachment.SystemId), 'Source header attachment should be cleaned up');
            Assert.IsFalse(DeletedAttachment.GetBySystemId(SourceLineAttachment.SystemId), 'Source line attachment should be cleaned up');
            RemainingHeaderAttachment := DestinationHeaderAttachment;
            RemainingLineAttachment := DestinationLineAttachment;
        end else begin
            if PostedCopy then begin
                PurchInvHeader.Delete(false);
                PurchInvLine.Delete(false);
            end else
                DeletePurchaseDocument(DestinationHeader, DestinationLine);
            Assert.IsFalse(DeletedAttachment.GetBySystemId(DestinationHeaderAttachment.SystemId), 'Destination header attachment should be cleaned up');
            Assert.IsFalse(DeletedAttachment.GetBySystemId(DestinationLineAttachment.SystemId), 'Destination line attachment should be cleaned up');
            RemainingHeaderAttachment := SourceHeaderAttachment;
            RemainingLineAttachment := SourceLineAttachment;
        end;

        // [THEN] Neither shared file has been deleted and the surviving attachments retain their metadata
        Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Document cleanup must not delete files still referenced by another document');
        RefreshAttachment(RemainingHeaderAttachment);
        RefreshAttachment(RemainingLineAttachment);
        Assert.AreEqual(SourceHeaderAttachment."External File Path", RemainingHeaderAttachment."External File Path", 'The surviving header must retain its file');
        Assert.AreEqual(SourceLineAttachment."External File Path", RemainingLineAttachment."External File Path", 'The surviving line must retain its file');
        Assert.IsTrue(RemainingHeaderAttachment."Stored Externally", 'The surviving header must remain externally stored');
        Assert.IsTrue(RemainingLineAttachment."Stored Externally", 'The surviving line must remain externally stored');

        // [WHEN] Each final reference is deleted separately
        RemainingLineAttachment.Delete(true);

        // [THEN] Final reference deletion respects the automatic deletion setting for each file independently
        if AutomaticDeletion then
            Assert.AreEqual(SourceLineAttachment."External File Path", FileConnectorMock.GetLastDeletedPath(), 'The final line reference must delete its file')
        else
            Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Automatic deletion disabled must preserve the file after its final line reference is deleted');
        RemainingHeaderAttachment.Delete(true);
        if AutomaticDeletion then
            Assert.AreEqual(SourceHeaderAttachment."External File Path", FileConnectorMock.GetLastDeletedPath(), 'The final header reference must delete its file')
        else
            Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Automatic deletion disabled must preserve the file after its final header reference is deleted');

        if SourceFirst then
            if PostedCopy then begin
                PurchInvHeader.Delete(false);
                PurchInvLine.Delete(false);
            end else
                DeletePurchaseDocument(DestinationHeader, DestinationLine)
        else
            DeletePurchaseDocument(SourceHeader, SourceLine);
    end;

    local procedure CreatePurchaseDocument(var PurchaseHeader: Record "Purchase Header"; var PurchaseLine: Record "Purchase Line"; DocumentType: Enum "Purchase Document Type")
    begin
        PurchaseHeader.Init();
        PurchaseHeader."Document Type" := DocumentType;
        PurchaseHeader."No." := CopyStr(Any.AlphanumericText(20), 1, MaxStrLen(PurchaseHeader."No."));
        PurchaseHeader.Insert(false);
        PurchaseLine.Init();
        PurchaseLine."Document Type" := DocumentType;
        PurchaseLine."Document No." := PurchaseHeader."No.";
        PurchaseLine."Line No." := 10000;
        PurchaseLine.Insert(false);
    end;

    local procedure CreatePurchaseAttachment(var DocumentAttachment: Record "Document Attachment"; PurchaseHeader: Record "Purchase Header"; LineNo: Integer)
    var
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        AttachmentDocumentType: Enum "Attachment Document Type";
        TableId: Integer;
    begin
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        if LineNo = 0 then
            TableId := Database::"Purchase Header"
        else
            TableId := Database::"Purchase Line";
        AttachmentDocumentType := Enum::"Attachment Document Type".FromInteger(PurchaseHeader."Document Type".AsInteger());
        DocumentAttachment.Rename(TableId, PurchaseHeader."No.", AttachmentDocumentType, LineNo, DocumentAttachment.ID);
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(DocumentAttachment), 'Purchase attachment upload should succeed');
        RefreshAttachment(DocumentAttachment);
    end;

    local procedure GetCopiedAttachment(var CopiedAttachment: Record "Document Attachment"; SourceAttachment: Record "Document Attachment"; TableId: Integer; DocumentNo: Code[20]; DocumentType: Enum "Attachment Document Type")
    begin
        CopiedAttachment.Get(TableId, DocumentNo, DocumentType, SourceAttachment."Line No.", SourceAttachment.ID);
    end;

    local procedure AssertCopiedExternalReference(SourceAttachment: Record "Document Attachment"; CopiedAttachment: Record "Document Attachment")
    begin
        Assert.AreNotEqual(SourceAttachment.SystemId, CopiedAttachment.SystemId, 'Copies must be distinct attachment records');
        Assert.AreEqual(SourceAttachment."External File Path", CopiedAttachment."External File Path", 'Copies must share the external file path');
        Assert.IsTrue(CopiedAttachment."Stored Externally", 'Copies must remain externally stored');
        Assert.AreEqual(SourceAttachment."Source Environment Hash", CopiedAttachment."Source Environment Hash", 'Copies must retain ownership metadata');
        Assert.IsFalse(CopiedAttachment."Skip Delete On Copy", 'New copies must not set the legacy deletion flag');
    end;

    local procedure DeletePurchaseDocument(var PurchaseHeader: Record "Purchase Header"; var PurchaseLine: Record "Purchase Line")
    begin
        // Delete(false) still invokes the document attachment cleanup subscribers, without financial validation.
        PurchaseHeader.Delete(false);
        PurchaseLine.Delete(false);
    end;

    local procedure AssertExternalMetadataCleared(var DocumentAttachment: Record "Document Attachment")
    begin
        RefreshAttachment(DocumentAttachment);
        Assert.IsFalse(DocumentAttachment."Stored Externally", 'The attachment should no longer be externally stored');
        Assert.AreEqual('', DocumentAttachment."External File Path", 'The external file path should be cleared');
        Assert.AreEqual(0DT, DocumentAttachment."External Upload Date", 'The external upload date should be cleared');
    end;

    local procedure VerifyExplicitRemoveOfSharedFile(AutomaticDeletion: Boolean)
    var
        SourceAttachment: Record "Document Attachment";
        CopiedAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ExternalFilePath: Text;
    begin
        // [SCENARIO] Explicit external removal releases only the current reference, independent of automatic record deletion
        Initialize();
        SetupFileScenarioWithTestConnector();
        if AutomaticDeletion then
            EnableFeatureWithDelete()
        else
            EnableFeature();

        // [GIVEN] Two attachment records sharing an uploaded file
        CreateDocumentAttachmentWithContent(SourceAttachment);
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(SourceAttachment), 'Upload should succeed');
        CreateCopyOfDocumentAttachment(SourceAttachment, CopiedAttachment);
        ExternalFilePath := SourceAttachment."External File Path";

        // [WHEN] The source external reference is explicitly removed
        Assert.IsTrue(DAExternalStorageImpl.DeleteFromExternalStorage(SourceAttachment), 'Explicit removal of a shared reference should succeed');

        // [THEN] Only its metadata is cleared and the destination remains usable
        AssertExternalMetadataCleared(SourceAttachment);
        Assert.IsTrue(SourceAttachment."Stored Internally", 'Explicit external removal must preserve internal storage');
        Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Explicit removal must keep a file referenced by another record');
        RefreshAttachment(CopiedAttachment);
        Assert.IsTrue(CopiedAttachment."Stored Externally", 'The other reference should remain externally stored');
        Assert.AreEqual(ExternalFilePath, CopiedAttachment."External File Path", 'The other reference must retain its path');

        // [WHEN] The destination external reference is explicitly removed
        Assert.IsTrue(DAExternalStorageImpl.DeleteFromExternalStorage(CopiedAttachment), 'Explicit removal of the last reference should succeed');

        // [THEN] The last reference deletes the file even when automatic record deletion is disabled
        AssertExternalMetadataCleared(CopiedAttachment);
        Assert.AreEqual(ExternalFilePath, FileConnectorMock.GetLastDeletedPath(), 'Explicit removal of the final reference must delete its file');
    end;

    local procedure VerifySyncMoveOfSharedFile(AutomaticDeletion: Boolean)
    var
        SourceAttachment: Record "Document Attachment";
        CopiedAttachment: Record "Document Attachment";
        DAExternalStorageImpl: Codeunit "DA External Storage Impl.";
        ExternalFilePath: Text;
    begin
        // [SCENARIO] Storage Sync Move to Internal releases shared references and deletes only the final external file
        Initialize();
        SetupFileScenarioWithTestConnector();
        FileConnectorMock.SetFileContent('Content restored from external storage');
        if AutomaticDeletion then
            EnableFeatureWithDelete()
        else
            EnableFeature();

        // [GIVEN] Two external-only attachment records sharing one file
        CreateDocumentAttachmentWithContent(SourceAttachment);
        Assert.IsTrue(DAExternalStorageImpl.UploadToExternalStorage(SourceAttachment), 'Upload should succeed');
        CreateCopyOfDocumentAttachment(SourceAttachment, CopiedAttachment);
        ExternalFilePath := SourceAttachment."External File Path";
        Assert.IsTrue(DAExternalStorageImpl.DeleteFromInternalStorage(SourceAttachment), 'Source internal removal should succeed');
        Assert.IsTrue(DAExternalStorageImpl.DeleteFromInternalStorage(CopiedAttachment), 'Destination internal removal should succeed');

        // [WHEN] The actual synchronization report moves only the source back to internal storage
        RunStorageSyncForAttachment(SourceAttachment);

        // [THEN] The source is restored internally and the other external reference is preserved
        AssertExternalMetadataCleared(SourceAttachment);
        Assert.IsTrue(SourceAttachment."Stored Internally", 'The source should be restored internally');
        Assert.IsTrue(SourceAttachment."Document Reference ID".HasValue(), 'The source should have restored content');
        Assert.AreEqual('', FileConnectorMock.GetLastDeletedPath(), 'Moving one shared reference must not delete the external file');
        RefreshAttachment(CopiedAttachment);
        Assert.IsTrue(CopiedAttachment."Stored Externally", 'The remaining reference should still be externally stored');
        Assert.IsFalse(CopiedAttachment."Stored Internally", 'The report filter must leave the other attachment external-only');
        Assert.AreEqual(ExternalFilePath, CopiedAttachment."External File Path", 'The remaining reference must retain the shared path');

        // [WHEN] The report moves the final reference back to internal storage
        RunStorageSyncForAttachment(CopiedAttachment);

        // [THEN] Both moves succeed and the last reference deletes the file regardless of automatic deletion
        AssertExternalMetadataCleared(CopiedAttachment);
        Assert.IsTrue(CopiedAttachment."Stored Internally", 'The destination should be restored internally');
        Assert.IsTrue(CopiedAttachment."Document Reference ID".HasValue(), 'The destination should have restored content');
        Assert.AreEqual(ExternalFilePath, FileConnectorMock.GetLastDeletedPath(), 'Move must delete the final external file even when automatic deletion is disabled');
    end;

    local procedure RunStorageSyncForAttachment(var DocumentAttachment: Record "Document Attachment")
    var
        AttachmentRecRef: RecordRef;
        MoveToInternalParametersLbl: Label '<?xml version="1.0" standalone="yes"?><ReportParameters name="DA External Storage Sync" id="%1"><Options><Field name="SyncDirectionField">1</Field><Field name="OperationField">1</Field><Field name="MaxRecordsToProcessField">0</Field></Options><DataItems></DataItems></ReportParameters>', Comment = '%1 = Storage synchronization report ID', Locked = true;
    begin
        DocumentAttachment.SetRecFilter();
        AttachmentRecRef.GetTable(DocumentAttachment);
        // The report has no parameter setter; Execute supplies its Move options without opening a request page.
        Report.Execute(Report::"DA External Storage Sync", StrSubstNo(MoveToInternalParametersLbl, Report::"DA External Storage Sync"), AttachmentRecRef);
        DocumentAttachment.Reset();
    end;

    local procedure Initialize()
    var
        DAExternalStorageSetup: Record "DA External Storage Setup";
        DocumentAttachment: Record "Document Attachment";
    begin
        // Clean up test data
        DocumentAttachment.DeleteAll();
        if DAExternalStorageSetup.Get() then
            DAExternalStorageSetup.Delete();

        // Clean up file scenario mappings using mock
        FileScenarioMock.DeleteAllMappings();

        // Initialize file connector mock
        FileConnectorMock.Initialize();
    end;

    local procedure SetupFileScenarioWithTestConnector()
    var
        AccountId: Guid;
    begin
        // Add a test account
        FileConnectorMock.AddAccount(AccountId);

        // Set up file scenario to use test connector using the mock
        FileScenarioMock.AddMapping(
            Enum::"File Scenario"::"Doc. Attach. - External Storage",
            AccountId,
            Enum::"Ext. File Storage Connector"::"Test File Storage Connector"
        );
    end;

    local procedure EnableFeature()
    var
        DAExternalStorageSetup: Record "DA External Storage Setup";
    begin
        if not DAExternalStorageSetup.Get() then begin
            DAExternalStorageSetup.Init();
            DAExternalStorageSetup.Insert();
        end;
        DAExternalStorageSetup.Validate(Enabled, true);
        DAExternalStorageSetup.Validate("Delete from External Storage", false);
        DAExternalStorageSetup.Modify();
    end;

    local procedure EnableFeatureOnly()
    var
        DAExternalStorageSetup: Record "DA External Storage Setup";
    begin
        // Enable with confirm handler
        if not DAExternalStorageSetup.Get() then begin
            DAExternalStorageSetup.Init();
            DAExternalStorageSetup.Insert();
        end;
        DAExternalStorageSetup.Validate(Enabled, true);
        DAExternalStorageSetup.Validate("Delete from External Storage", false);
        DAExternalStorageSetup.Modify();
    end;

    local procedure EnableFeatureWithDelete()
    var
        DAExternalStorageSetup: Record "DA External Storage Setup";
    begin
        if not DAExternalStorageSetup.Get() then begin
            DAExternalStorageSetup.Init();
            DAExternalStorageSetup.Insert();
        end;
        DAExternalStorageSetup.Validate(Enabled, true);
        DAExternalStorageSetup.Validate("Delete from External Storage", true);
        DAExternalStorageSetup.Modify();
    end;

    local procedure CreateDocumentAttachmentWithContent(var DocumentAttachment: Record "Document Attachment")
    var
        TempBlob: Codeunit "Temp Blob";
        InStream: InStream;
        OutStream: OutStream;
    begin
        TempBlob.CreateOutStream(OutStream, TextEncoding::UTF8);
        OutStream.WriteText('Test content for attachment ' + Any.AlphanumericText(10));
        TempBlob.CreateInStream(InStream);

        DocumentAttachment.Init();
        DocumentAttachment.ID := Any.IntegerInRange(10000, 99999);
        DocumentAttachment."Table ID" := Database::"Document Attachment";
        DocumentAttachment."No." := CopyStr(Any.AlphanumericText(20), 1, 20);
        DocumentAttachment."File Name" := 'TestFile_' + CopyStr(Any.AlphanumericText(5), 1, 5);
        DocumentAttachment."File Extension" := 'txt';
        DocumentAttachment."Stored Internally" := true;
        DocumentAttachment.Insert(false);
        DocumentAttachment.ImportAttachment(InStream, DocumentAttachment."File Name" + '.txt');
        DocumentAttachment.Modify(false);
    end;

    local procedure CreateCopyOfDocumentAttachment(var DocumentAttachment: Record "Document Attachment"; var CopiedDocumentAttachment: Record "Document Attachment")
    begin
        // Mirrors Document Attachment Mgmt, which copies attachments onto posted documents with
        // TransferFields. That copies the media reference itself, so both records end up sharing
        // a single Tenant Media row.
        CopiedDocumentAttachment.Init();
        CopiedDocumentAttachment.TransferFields(DocumentAttachment);
        CopiedDocumentAttachment.ID := DocumentAttachment.ID + 1;
        CopiedDocumentAttachment."No." := CopyStr(Any.AlphanumericText(20), 1, 20);
        CopiedDocumentAttachment.Insert(false);

        Assert.AreEqual(
            DocumentAttachment."Document Reference ID".MediaId(),
            CopiedDocumentAttachment."Document Reference ID".MediaId(),
            'The copied attachment is expected to share the media of the attachment it was copied from');
    end;

    local procedure CreateExternallyStoredDocument(var DocumentAttachment: Record "Document Attachment")
    begin
        CreateDocumentAttachmentWithContent(DocumentAttachment);
        DocumentAttachment."Stored Externally" := true;
        DocumentAttachment."External File Path" := 'test/environment/Document_Attachment/file-' + Format(CreateGuid()) + '.txt';
        DocumentAttachment."External Upload Date" := CurrentDateTime();
        DocumentAttachment.Modify();
    end;

    local procedure CreateExternallyStoredOnlyDocument(var DocumentAttachment: Record "Document Attachment")
    begin
        DocumentAttachment.Init();
        DocumentAttachment.ID := Any.IntegerInRange(10000, 99999);
        DocumentAttachment."Table ID" := Database::"Document Attachment";
        DocumentAttachment."No." := CopyStr(Any.AlphanumericText(20), 1, 20);
        DocumentAttachment."File Name" := 'TestFile';
        DocumentAttachment."File Extension" := 'txt';
        DocumentAttachment."Stored Externally" := true;
        DocumentAttachment."Stored Internally" := false;
        DocumentAttachment."External File Path" := 'test/path/file.txt';
        DocumentAttachment.Insert();
    end;

    local procedure RefreshAttachment(var DocumentAttachment: Record "Document Attachment")
    begin
        DocumentAttachment.Get(
            DocumentAttachment."Table ID",
            DocumentAttachment."No.",
            DocumentAttachment."Document Type",
            DocumentAttachment."Line No.",
            DocumentAttachment.ID);
    end;

    [ConfirmHandler]
    procedure ConfirmYesHandler(Question: Text[1024]; var Reply: Boolean)
    begin
        Reply := true;
    end;

    [MessageHandler]
    procedure SyncMessageHandler(Message: Text[1024])
    begin
        Assert.AreEqual('Processed 1 attachments successfully. 0 failed.', Message, 'Each filtered synchronization run should move one attachment successfully');
    end;

    #endregion
}

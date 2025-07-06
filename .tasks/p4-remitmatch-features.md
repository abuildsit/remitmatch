# Phase 4: RemitMatch Core Features

## Overview
This phase implements the core RemitMatch functionality including file upload, PDF processing, remittance management UI, and the complete workflow from upload to approval.

## Prerequisites
- Phases 1-3 completed
- OpenAI API key for PDF extraction
- Local Supabase running with storage configured
- Organisation context working

## Phase 4.1: File Upload System

### Objective
Implement secure file upload to Supabase Storage with proper validation and organisation-based access control.

### Tasks
- [ ] Add OpenAI and file processing dependencies to `apps/api/requirements.txt`:
  ```
  openai==1.3.0
  pypdf2==3.0.1
  python-multipart==0.0.6
  aiofiles==23.2.1
  ```
- [ ] Update `apps/api/app/config.py` with OpenAI settings:
  ```python
  # Add to Settings class
  OPENAI_API_KEY: str
  OPENAI_MODEL: str = "gpt-4-turbo-preview"
  ```
- [ ] Create file upload models in `apps/api/app/models/files.py`:
  ```python
  from pydantic import BaseModel
  from typing import Optional
  import uuid
  from datetime import datetime
  
  class FileUploadResponse(BaseModel):
      file_id: str
      file_name: str
      file_path: str
      remittance_id: str
      status: str = "uploaded"
  
  class FileMetadata(BaseModel):
      id: uuid.UUID
      organisation_id: uuid.UUID
      remittance_id: uuid.UUID
      file_name: str
      file_path: str
      file_size: int
      mime_type: str
      uploaded_by: str
      created_at: datetime
  ```
- [ ] Create storage service in `apps/api/app/services/storage_service.py`:
  ```python
  from supabase import Client
  from app.database import get_db
  from typing import BinaryIO, Dict, Any
  import uuid
  import os
  from datetime import datetime
  
  class StorageService:
      def __init__(self):
          self.bucket_name = "remittance-files"
          
      async def upload_file(
          self,
          file: BinaryIO,
          file_name: str,
          organisation_id: str,
          remittance_id: str,
          user_id: str,
          mime_type: str = "application/pdf"
      ) -> Dict[str, Any]:
          """Upload file to Supabase Storage"""
          db = get_db()
          
          # Generate file path: {organisation_id}/{remittance_id}/{file_name}
          file_path = f"{organisation_id}/{remittance_id}/{file_name}"
          
          try:
              # Upload to Supabase Storage
              response = db.storage.from_(self.bucket_name).upload(
                  path=file_path,
                  file=file,
                  file_options={"content-type": mime_type}
              )
              
              # Get file size
              file.seek(0, 2)  # Seek to end
              file_size = file.tell()
              file.seek(0)  # Reset to beginning
              
              # Store file metadata in database
              file_metadata = {
                  'organisation_id': organisation_id,
                  'remittance_id': remittance_id,
                  'file_name': file_name,
                  'file_path': file_path,
                  'file_size': file_size,
                  'mime_type': mime_type,
                  'uploaded_by': user_id
              }
              
              file_result = db.table('files').insert(file_metadata).execute()
              
              return {
                  'file_id': file_result.data[0]['id'],
                  'file_path': file_path,
                  'file_name': file_name
              }
              
          except Exception as e:
              raise Exception(f"Failed to upload file: {str(e)}")
      
      async def get_file_url(self, file_path: str, expires_in: int = 3600) -> str:
          """Get a signed URL for file access"""
          db = get_db()
          
          try:
              response = db.storage.from_(self.bucket_name).create_signed_url(
                  path=file_path,
                  expires_in=expires_in
              )
              return response['signedURL']
          except Exception as e:
              raise Exception(f"Failed to get file URL: {str(e)}")
      
      async def delete_file(self, file_path: str) -> bool:
          """Delete file from storage"""
          db = get_db()
          
          try:
              response = db.storage.from_(self.bucket_name).remove([file_path])
              return True
          except Exception as e:
              raise Exception(f"Failed to delete file: {str(e)}")
  ```
- [ ] Create file upload endpoint in `apps/api/app/routers/files.py`:
  ```python
  from fastapi import APIRouter, HTTPException, Header, UploadFile, File, Form
  from app.services.storage_service import StorageService
  from app.models.files import FileUploadResponse
  from app.models.database import RemittanceStatus
  from app.utils.database_helpers import check_organisation_access, create_audit_log
  from app.database import get_db
  import uuid
  from typing import Optional
  
  router = APIRouter()
  storage_service = StorageService()
  
  ALLOWED_MIME_TYPES = ["application/pdf"]
  MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
  
  @router.post("/upload", response_model=FileUploadResponse)
  async def upload_remittance_file(
      file: UploadFile = File(...),
      organisation_id: str = Form(...),
      user_id: str = Header(...)
  ):
      """Upload a remittance PDF file"""
      # Check organisation access
      if not await check_organisation_access(user_id, organisation_id):
          raise HTTPException(status_code=403, detail="Access denied")
      
      # Validate file type
      if file.content_type not in ALLOWED_MIME_TYPES:
          raise HTTPException(status_code=400, detail="Only PDF files are allowed")
      
      # Validate file size
      contents = await file.read()
      if len(contents) > MAX_FILE_SIZE:
          raise HTTPException(status_code=400, detail="File size exceeds 10MB limit")
      
      # Reset file position
      await file.seek(0)
      
      try:
          db = get_db()
          
          # Create remittance record
          remittance_id = str(uuid.uuid4())
          remittance_data = {
              'id': remittance_id,
              'organisation_id': organisation_id,
              'status': RemittanceStatus.UPLOADED,
              'created_by': user_id
          }
          
          remittance_result = db.table('remittances').insert(remittance_data).execute()
          
          # Upload file
          file_result = await storage_service.upload_file(
              file=file.file,
              file_name=file.filename,
              organisation_id=organisation_id,
              remittance_id=remittance_id,
              user_id=user_id,
              mime_type=file.content_type
          )
          
          # Create audit log
          await create_audit_log(
              organisation_id=organisation_id,
              user_id=user_id,
              action='remittance_uploaded',
              remittance_id=remittance_id,
              field_name='file_name',
              new_value=file.filename,
              outcome='success'
          )
          
          # Trigger processing (async - fire and forget)
          # This will be implemented in the next section
          
          return FileUploadResponse(
              file_id=file_result['file_id'],
              file_name=file.filename,
              file_path=file_result['file_path'],
              remittance_id=remittance_id,
              status=RemittanceStatus.UPLOADED
          )
          
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  
  @router.get("/{remittance_id}/download")
  async def get_remittance_file(
      remittance_id: str,
      user_id: str = Header(...)
  ):
      """Get signed URL for remittance file download"""
      try:
          db = get_db()
          
          # Get remittance and check access
          remittance = db.table('remittances').select(
              '*, files(*)'
          ).eq('id', remittance_id).execute()
          
          if not remittance.data:
              raise HTTPException(status_code=404, detail="Remittance not found")
          
          # Check organisation access
          if not await check_organisation_access(user_id, remittance.data[0]['organisation_id']):
              raise HTTPException(status_code=403, detail="Access denied")
          
          # Get file
          files = remittance.data[0].get('files', [])
          if not files:
              raise HTTPException(status_code=404, detail="No file found")
          
          file = files[0]
          
          # Get signed URL
          signed_url = await storage_service.get_file_url(file['file_path'])
          
          return {
              'url': signed_url,
              'file_name': file['file_name'],
              'mime_type': file['mime_type']
          }
          
      except HTTPException:
          raise
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  ```
- [ ] Update main.py to include files router:
  ```python
  from app.routers import stripe, test, organisations, users, xero, files
  
  app.include_router(files.router, prefix="/files", tags=["files"])
  ```
- [ ] Create file upload component in `apps/web/components/file-upload.tsx`:
  ```typescript
  'use client';
  
  import { useState, useCallback } from 'react';
  import { useDropzone } from 'react-dropzone';
  import { Upload, X, FileText, Loader2 } from 'lucide-react';
  import { Button } from '@/components/ui/button';
  import { toast } from 'sonner';
  import { useSession } from '@/lib/hooks/use-session';
  
  interface FileUploadProps {
    onUploadComplete: (remittanceId: string) => void;
    onCancel: () => void;
  }
  
  export function FileUpload({ onUploadComplete, onCancel }: FileUploadProps) {
    const [file, setFile] = useState<File | null>(null);
    const [uploading, setUploading] = useState(false);
    const { organisation, user } = useSession();
    
    const onDrop = useCallback((acceptedFiles: File[]) => {
      if (acceptedFiles.length > 0) {
        const uploadedFile = acceptedFiles[0];
        
        // Validate file type
        if (uploadedFile.type !== 'application/pdf') {
          toast.error('Only PDF files are allowed');
          return;
        }
        
        // Validate file size (10MB)
        if (uploadedFile.size > 10 * 1024 * 1024) {
          toast.error('File size must be less than 10MB');
          return;
        }
        
        setFile(uploadedFile);
      }
    }, []);
    
    const { getRootProps, getInputProps, isDragActive } = useDropzone({
      onDrop,
      accept: {
        'application/pdf': ['.pdf']
      },
      maxFiles: 1
    });
    
    const handleUpload = async () => {
      if (!file || !organisation.id || !user.id) return;
      
      setUploading(true);
      const formData = new FormData();
      formData.append('file', file);
      formData.append('organisation_id', organisation.id);
      
      try {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/files/upload`,
          {
            method: 'POST',
            headers: {
              'user-id': user.id
            },
            body: formData
          }
        );
        
        if (!response.ok) {
          throw new Error('Upload failed');
        }
        
        const data = await response.json();
        toast.success('File uploaded successfully');
        onUploadComplete(data.remittance_id);
        
      } catch (error) {
        toast.error('Failed to upload file');
        console.error('Upload error:', error);
      } finally {
        setUploading(false);
      }
    };
    
    const removeFile = () => {
      setFile(null);
    };
    
    return (
      <div className="space-y-4">
        {!file ? (
          <div
            {...getRootProps()}
            className={`
              border-2 border-dashed rounded-lg p-8 text-center cursor-pointer
              transition-colors duration-200
              ${isDragActive 
                ? 'border-primary bg-primary/5' 
                : 'border-gray-300 hover:border-gray-400'
              }
            `}
          >
            <input {...getInputProps()} />
            <Upload className="mx-auto h-12 w-12 text-gray-400 mb-4" />
            <p className="text-sm text-gray-600">
              {isDragActive
                ? 'Drop the PDF here...'
                : 'Drag and drop a PDF file here, or click to select'
              }
            </p>
            <p className="text-xs text-gray-500 mt-2">
              Only PDF files up to 10MB are supported
            </p>
          </div>
        ) : (
          <div className="border rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <FileText className="h-8 w-8 text-blue-500" />
                <div>
                  <p className="font-medium text-sm">{file.name}</p>
                  <p className="text-xs text-gray-500">
                    {(file.size / 1024 / 1024).toFixed(2)} MB
                  </p>
                </div>
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={removeFile}
                disabled={uploading}
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
          </div>
        )}
        
        <div className="flex gap-2 justify-end">
          <Button variant="outline" onClick={onCancel} disabled={uploading}>
            Cancel
          </Button>
          <Button 
            onClick={handleUpload} 
            disabled={!file || uploading}
          >
            {uploading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Uploading...
              </>
            ) : (
              'Upload'
            )}
          </Button>
        </div>
      </div>
    );
  }
  ```
- [ ] Install react-dropzone:
  ```bash
  cd apps/web
  npm install react-dropzone
  ```
- [ ] Test file upload flow
- [ ] Verify files are stored in Supabase Storage
- [ ] Check file metadata is saved to database

## Phase 4.2: Remittance Processing Backend

### Objective
Implement AI-powered PDF extraction and remittance processing logic.

### Tasks
- [ ] Create OpenAI service in `apps/api/app/services/openai_service.py`:
  ```python
  import openai
  from app.config import settings
  import json
  from typing import Dict, Any, List
  import PyPDF2
  import io
  
  class OpenAIService:
      def __init__(self):
          openai.api_key = settings.OPENAI_API_KEY
          self.model = settings.OPENAI_MODEL
          
      async def extract_remittance_data(self, pdf_content: bytes) -> Dict[str, Any]:
          """Extract remittance data from PDF using OpenAI"""
          # Extract text from PDF
          pdf_text = self._extract_pdf_text(pdf_content)
          
          # System prompt for extraction
          system_prompt = """You are a remittance advice reader tasked with extracting specific information from a PDF file of a remittance advice and presenting it as a valid JSON object.
  
  Extract the following information:
  - Date: The payment date (not invoice date). Format as YYYY-MM-DD.
  - TotalAmount: The total amount paid.
  - PaymentReference: The reference number for the payment. If no reference is present, use null.
  - Payments: Array of invoice payments with InvoiceNo and PaidAmount.
  - confidence: Your confidence in the extraction accuracy (0-100).
  
  Return ONLY a valid JSON object with this exact structure:
  {
    "Date": "YYYY-MM-DD",
    "TotalAmount": 0.00,
    "PaymentReference": "string or null",
    "Payments": [
      {
        "InvoiceNo": "string",
        "PaidAmount": 0.00
      }
    ],
    "confidence": 0
  }"""
          
          try:
              response = openai.ChatCompletion.create(
                  model=self.model,
                  messages=[
                      {"role": "system", "content": system_prompt},
                      {"role": "user", "content": f"Extract remittance data from this text:\n\n{pdf_text}"}
                  ],
                  temperature=0.1,
                  max_tokens=1000
              )
              
              # Parse the response
              result = json.loads(response.choices[0].message.content)
              
              # Validate the response structure
              required_fields = ['Date', 'TotalAmount', 'PaymentReference', 'Payments', 'confidence']
              for field in required_fields:
                  if field not in result:
                      raise ValueError(f"Missing required field: {field}")
              
              return result
              
          except json.JSONDecodeError:
              # If JSON parsing fails, return error structure
              return {
                  "Date": None,
                  "TotalAmount": 0,
                  "PaymentReference": None,
                  "Payments": [],
                  "confidence": 0,
                  "error": "Failed to parse AI response"
              }
          except Exception as e:
              return {
                  "Date": None,
                  "TotalAmount": 0,
                  "PaymentReference": None,
                  "Payments": [],
                  "confidence": 0,
                  "error": str(e)
              }
      
      def _extract_pdf_text(self, pdf_content: bytes) -> str:
          """Extract text from PDF bytes"""
          try:
              pdf_file = io.BytesIO(pdf_content)
              pdf_reader = PyPDF2.PdfReader(pdf_file)
              
              text = ""
              for page_num in range(len(pdf_reader.pages)):
                  page = pdf_reader.pages[page_num]
                  text += page.extract_text() + "\n"
              
              return text.strip()
          except Exception as e:
              raise Exception(f"Failed to extract PDF text: {str(e)}")
  ```
- [ ] Create remittance processing service in `apps/api/app/services/remittance_service.py`:
  ```python
  from app.services.openai_service import OpenAIService
  from app.services.storage_service import StorageService
  from app.database import get_db
  from app.models.database import RemittanceStatus
  from app.utils.database_helpers import create_audit_log
  from typing import Dict, Any, Optional
  import httpx
  from datetime import datetime
  
  class RemittanceService:
      def __init__(self):
          self.openai_service = OpenAIService()
          self.storage_service = StorageService()
          
      async def process_remittance(self, remittance_id: str) -> Dict[str, Any]:
          """Process a remittance file with AI extraction"""
          db = get_db()
          
          try:
              # Get remittance and file info
              result = db.table('remittances').select(
                  '*, files(*)'
              ).eq('id', remittance_id).execute()
              
              if not result.data:
                  raise Exception("Remittance not found")
              
              remittance = result.data[0]
              files = remittance.get('files', [])
              
              if not files:
                  raise Exception("No file found for remittance")
              
              file = files[0]
              
              # Update status to processing
              db.table('remittances').update({
                  'status': RemittanceStatus.DATA_RETRIEVED
              }).eq('id', remittance_id).execute()
              
              # Get file content from storage
              file_url = await self.storage_service.get_file_url(file['file_path'])
              
              async with httpx.AsyncClient() as client:
                  response = await client.get(file_url)
                  pdf_content = response.content
              
              # Extract data using AI
              extraction_result = await self.openai_service.extract_remittance_data(pdf_content)
              
              if 'error' in extraction_result:
                  # Update status to error
                  db.table('remittances').update({
                      'status': RemittanceStatus.ERROR_UNMATCHED
                  }).eq('id', remittance_id).execute()
                  
                  await create_audit_log(
                      organisation_id=remittance['organisation_id'],
                      user_id='system',
                      action='extraction_failed',
                      remittance_id=remittance_id,
                      outcome='error',
                      field_name='error',
                      new_value=extraction_result['error']
                  )
                  
                  return {'status': 'error', 'message': extraction_result['error']}
              
              # Update remittance with extracted data
              update_data = {
                  'payment_date': extraction_result['Date'],
                  'total_amount': extraction_result['TotalAmount'],
                  'payment_reference': extraction_result['PaymentReference'],
                  'confidence_score': extraction_result['confidence'] / 100.0,
                  'status': RemittanceStatus.ALL_MATCHED_AWAITING if extraction_result['confidence'] > 50 else RemittanceStatus.ERROR_UNMATCHED
              }
              
              db.table('remittances').update(update_data).eq('id', remittance_id).execute()
              
              # Create remittance lines
              for payment in extraction_result['Payments']:
                  line_data = {
                      'remittance_id': remittance_id,
                      'invoice_number': payment['InvoiceNo'],
                      'ai_paid_amount': payment['PaidAmount']
                  }
                  db.table('remittance_lines').insert(line_data).execute()
              
              # Create audit log
              await create_audit_log(
                  organisation_id=remittance['organisation_id'],
                  user_id='system',
                  action='extraction_completed',
                  remittance_id=remittance_id,
                  outcome='success',
                  field_name='confidence',
                  new_value=str(extraction_result['confidence'])
              )
              
              return {
                  'status': 'success',
                  'confidence': extraction_result['confidence'],
                  'payment_count': len(extraction_result['Payments'])
              }
              
          except Exception as e:
              # Log error and update status
              db.table('remittances').update({
                  'status': RemittanceStatus.ERROR_UNMATCHED
              }).eq('id', remittance_id).execute()
              
              return {'status': 'error', 'message': str(e)}
      
      async def retry_extraction(self, remittance_id: str, user_id: str) -> Dict[str, Any]:
          """Retry AI extraction for a remittance"""
          db = get_db()
          
          # Delete existing remittance lines
          db.table('remittance_lines').delete().eq('remittance_id', remittance_id).execute()
          
          # Reset status
          db.table('remittances').update({
              'status': RemittanceStatus.DATA_RETRIEVED,
              'payment_date': None,
              'total_amount': None,
              'payment_reference': None,
              'confidence_score': None
          }).eq('id', remittance_id).execute()
          
          # Create audit log
          remittance = db.table('remittances').select('organisation_id').eq('id', remittance_id).execute()
          await create_audit_log(
              organisation_id=remittance.data[0]['organisation_id'],
              user_id=user_id,
              action='extraction_retry',
              remittance_id=remittance_id,
              outcome='initiated'
          )
          
          # Reprocess
          return await self.process_remittance(remittance_id)
  ```
- [ ] Create remittance processing endpoint in `apps/api/app/routers/remittances.py`:
  ```python
  from fastapi import APIRouter, HTTPException, Header, BackgroundTasks
  from app.services.remittance_service import RemittanceService
  from app.database import get_db
  from app.utils.database_helpers import check_organisation_access
  from typing import Optional
  
  router = APIRouter()
  remittance_service = RemittanceService()
  
  @router.post("/{remittance_id}/process")
  async def process_remittance(
      remittance_id: str,
      background_tasks: BackgroundTasks,
      user_id: str = Header(...)
  ):
      """Trigger processing for a remittance"""
      db = get_db()
      
      # Get remittance
      result = db.table('remittances').select('organisation_id').eq('id', remittance_id).execute()
      if not result.data:
          raise HTTPException(status_code=404, detail="Remittance not found")
      
      # Check access
      if not await check_organisation_access(user_id, result.data[0]['organisation_id']):
          raise HTTPException(status_code=403, detail="Access denied")
      
      # Process in background
      background_tasks.add_task(remittance_service.process_remittance, remittance_id)
      
      return {"status": "processing_started", "remittance_id": remittance_id}
  
  @router.post("/{remittance_id}/retry")
  async def retry_extraction(
      remittance_id: str,
      user_id: str = Header(...)
  ):
      """Retry AI extraction for a remittance"""
      db = get_db()
      
      # Get remittance
      result = db.table('remittances').select('organisation_id, status').eq('id', remittance_id).execute()
      if not result.data:
          raise HTTPException(status_code=404, detail="Remittance not found")
      
      remittance = result.data[0]
      
      # Check access
      if not await check_organisation_access(user_id, remittance['organisation_id']):
          raise HTTPException(status_code=403, detail="Access denied")
      
      # Check status - can only retry if in error state
      if remittance['status'] not in ['Error - Payments Unmatched', 'Data Retrieved']:
          raise HTTPException(status_code=400, detail="Cannot retry extraction in current status")
      
      # Retry extraction
      result = await remittance_service.retry_extraction(remittance_id, user_id)
      
      return result
  ```
- [ ] Update file upload to trigger processing automatically:
  ```python
  # In apps/api/app/routers/files.py, add to upload_remittance_file:
  from fastapi import BackgroundTasks
  from app.services.remittance_service import RemittanceService
  
  remittance_service = RemittanceService()
  
  # Add background_tasks parameter to function
  async def upload_remittance_file(
      file: UploadFile = File(...),
      organisation_id: str = Form(...),
      user_id: str = Header(...),
      background_tasks: BackgroundTasks = None
  ):
      # ... existing code ...
      
      # After successful upload, trigger processing
      background_tasks.add_task(
          remittance_service.process_remittance, 
          remittance_id
      )
      
      return FileUploadResponse(...)
  ```
- [ ] Update main.py to include remittances router:
  ```python
  from app.routers import stripe, test, organisations, users, xero, files, remittances
  
  app.include_router(remittances.router, prefix="/remittances", tags=["remittances"])
  ```
- [ ] Test PDF extraction with sample remittance files
- [ ] Verify extraction results are saved correctly

## Phase 4.3: Remittance UI - List View

### Objective
Create the remittances list view with filtering, pagination, and status display.

### Tasks
- [ ] Create remittance types in `apps/web/lib/types/remittance.ts`:
  ```typescript
  export type RemittanceStatus = 
    | 'Uploaded'
    | 'Data Retrieved'
    | 'All payments matched - Awaiting Approval'
    | 'Error - Payments Unmatched'
    | 'Exported to Xero - Unreconciled'
    | 'Exported to Xero - Reconciled'
    | 'Export Failed'
    | 'Soft Deleted';
  
  export interface Remittance {
    id: string;
    organisation_id: string;
    status: RemittanceStatus;
    payment_date: string | null;
    total_amount: number | null;
    payment_reference: string | null;
    confidence_score: number | null;
    xero_payment_id: string | null;
    created_by: string;
    created_at: string;
    updated_at: string;
    deleted_at: string | null;
    files?: RemittanceFile[];
    lines?: RemittanceLine[];
  }
  
  export interface RemittanceFile {
    id: string;
    file_name: string;
    file_path: string;
    file_size: number;
    mime_type: string;
  }
  
  export interface RemittanceLine {
    id: string;
    invoice_number: string;
    ai_paid_amount: number;
    manual_paid_amount: number | null;
    ai_invoice_id: string | null;
    override_invoice_id: string | null;
  }
  
  export const statusBadgeVariants: Record<RemittanceStatus, string> = {
    'Uploaded': 'secondary',
    'Data Retrieved': 'secondary',
    'All payments matched - Awaiting Approval': 'default',
    'Error - Payments Unmatched': 'destructive',
    'Exported to Xero - Unreconciled': 'outline',
    'Exported to Xero - Reconciled': 'success',
    'Export Failed': 'destructive',
    'Soft Deleted': 'secondary'
  };
  ```
- [ ] Create status badge component in `apps/web/components/status-badge.tsx`:
  ```typescript
  import { Badge } from '@/components/ui/badge';
  import { RemittanceStatus, statusBadgeVariants } from '@/lib/types/remittance';
  
  interface StatusBadgeProps {
    status: RemittanceStatus;
  }
  
  export function StatusBadge({ status }: StatusBadgeProps) {
    const variant = statusBadgeVariants[status] || 'default';
    
    // Shorten long status names for display
    const displayStatus = status
      .replace('All payments matched - ', '')
      .replace('Exported to Xero - ', '');
    
    return (
      <Badge variant={variant as any}>
        {displayStatus}
      </Badge>
    );
  }
  ```
- [ ] Create remittances list page in `apps/web/app/dashboard/remittances/page.tsx`:
  ```typescript
  'use client';
  
  import { useState, useEffect } from 'react';
  import { useQuery, useQueryClient } from '@tanstack/react-query';
  import { useSession } from '@/lib/hooks/use-session';
  import { useSessionStore } from '@/lib/stores/session';
  import { Button } from '@/components/ui/button';
  import { Input } from '@/components/ui/input';
  import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
  } from '@/components/ui/table';
  import {
    Dialog,
    DialogContent,
    DialogHeader,
    DialogTitle,
  } from '@/components/ui/dialog';
  import { FileUpload } from '@/components/file-upload';
  import { StatusBadge } from '@/components/status-badge';
  import { Remittance } from '@/lib/types/remittance';
  import { Upload, RefreshCw, Search, Loader2 } from 'lucide-react';
  import { format } from 'date-fns';
  import { useRouter } from 'next/navigation';
  import { toast } from 'sonner';
  
  export default function RemittancesPage() {
    const router = useRouter();
    const queryClient = useQueryClient();
    const { organisation, user } = useSession();
    const { setActiveRemittance } = useSessionStore();
    const [uploadOpen, setUploadOpen] = useState(false);
    const [searchTerm, setSearchTerm] = useState('');
    const [refreshing, setRefreshing] = useState(false);
    
    // Fetch remittances
    const { data, isLoading, error, refetch } = useQuery({
      queryKey: ['remittances', organisation.id],
      queryFn: async () => {
        if (!organisation.id) return { remittances: [] };
        
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/remittances?organisation_id=${organisation.id}`,
          {
            headers: {
              'user-id': user.id || ''
            }
          }
        );
        
        if (!response.ok) throw new Error('Failed to fetch remittances');
        return response.json();
      },
      enabled: !!organisation.id
    });
    
    const handleUploadComplete = (remittanceId: string) => {
      setUploadOpen(false);
      refetch();
      toast.success('File uploaded successfully. Processing started.');
    };
    
    const handleRefreshXero = async () => {
      setRefreshing(true);
      try {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/xero/sync-all`,
          {
            method: 'POST',
            headers: {
              'user-id': user.id || '',
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({ organisation_id: organisation.id })
          }
        );
        
        if (response.ok) {
          toast.success('Xero sync initiated');
          refetch();
        } else {
          toast.error('Failed to sync with Xero');
        }
      } catch (error) {
        toast.error('Failed to sync with Xero');
      } finally {
        setRefreshing(false);
      }
    };
    
    const handleRowClick = (remittance: Remittance) => {
      setActiveRemittance(remittance.id);
      router.push(`/dashboard/remittances/${remittance.id}`);
    };
    
    const filteredRemittances = data?.remittances?.filter((r: Remittance) => {
      if (!searchTerm) return true;
      const search = searchTerm.toLowerCase();
      return (
        r.payment_reference?.toLowerCase().includes(search) ||
        r.status.toLowerCase().includes(search) ||
        r.total_amount?.toString().includes(search)
      );
    }) || [];
    
    if (!organisation.id) {
      return (
        <div className="text-center py-8">
          <p>Please select an organisation to view remittances.</p>
        </div>
      );
    }
    
    return (
      <div className="space-y-6">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-3xl font-bold">Remittances</h1>
            <p className="text-muted-foreground">
              Manage and reconcile your remittance advices
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              variant="outline"
              onClick={handleRefreshXero}
              disabled={refreshing}
            >
              {refreshing ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <RefreshCw className="h-4 w-4" />
              )}
              Refresh from Xero
            </Button>
            <Button onClick={() => setUploadOpen(true)}>
              <Upload className="mr-2 h-4 w-4" />
              Upload Remittance
            </Button>
          </div>
        </div>
        
        <div className="flex items-center space-x-2">
          <Search className="h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search remittances..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="max-w-sm"
          />
        </div>
        
        <div className="border rounded-lg">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Status</TableHead>
                <TableHead>Date Added</TableHead>
                <TableHead>Payment Date</TableHead>
                <TableHead>Payment Amount</TableHead>
                <TableHead>Reference</TableHead>
                <TableHead># Invoices</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow>
                  <TableCell colSpan={6} className="text-center py-8">
                    <Loader2 className="h-6 w-6 animate-spin mx-auto" />
                  </TableCell>
                </TableRow>
              ) : filteredRemittances.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={6} className="text-center py-8">
                    No remittances found
                  </TableCell>
                </TableRow>
              ) : (
                filteredRemittances.map((remittance: Remittance) => (
                  <TableRow
                    key={remittance.id}
                    className="cursor-pointer hover:bg-muted/50"
                    onClick={() => handleRowClick(remittance)}
                  >
                    <TableCell>
                      <StatusBadge status={remittance.status} />
                    </TableCell>
                    <TableCell>
                      {format(new Date(remittance.created_at), 'dd/MM/yyyy')}
                    </TableCell>
                    <TableCell>
                      {remittance.payment_date
                        ? format(new Date(remittance.payment_date), 'dd/MM/yyyy')
                        : '-'}
                    </TableCell>
                    <TableCell>
                      {remittance.total_amount
                        ? `$${remittance.total_amount.toFixed(2)}`
                        : '-'}
                    </TableCell>
                    <TableCell>
                      {remittance.payment_reference || '-'}
                    </TableCell>
                    <TableCell>
                      {remittance.lines?.length || 0}
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </div>
        
        <Dialog open={uploadOpen} onOpenChange={setUploadOpen}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Upload Remittance</DialogTitle>
            </DialogHeader>
            <FileUpload
              onUploadComplete={handleUploadComplete}
              onCancel={() => setUploadOpen(false)}
            />
          </DialogContent>
        </Dialog>
      </div>
    );
  }
  ```
- [ ] Add remittances API endpoint for list in `apps/api/app/routers/remittances.py`:
  ```python
  from typing import List, Optional
  from fastapi import Query
  
  @router.get("/")
  async def get_remittances(
      organisation_id: str = Query(...),
      status: Optional[str] = Query(None),
      limit: int = Query(50, le=100),
      offset: int = Query(0),
      user_id: str = Header(...)
  ):
      """Get remittances for an organisation"""
      # Check access
      if not await check_organisation_access(user_id, organisation_id):
          raise HTTPException(status_code=403, detail="Access denied")
      
      try:
          db = get_db()
          
          # Build query
          query = db.table('remittances').select(
              '*, files(id, file_name), remittance_lines(id)'
          ).eq('organisation_id', organisation_id).is_('deleted_at', 'null')
          
          # Apply filters
          if status:
              query = query.eq('status', status)
          
          # Order and paginate
          query = query.order('created_at', desc=True).range(offset, offset + limit - 1)
          
          result = query.execute()
          
          # Transform data to include line count
          remittances = []
          for r in result.data:
              remittance = {**r}
              remittance['lines'] = r.get('remittance_lines', [])
              remittances.append(remittance)
          
          return {"remittances": remittances}
          
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  ```
- [ ] Test remittances list view
- [ ] Verify search and filtering work
- [ ] Check navigation to detail view

## Phase 4.4: Remittance UI - Detail View

### Objective
Create the detailed remittance view with PDF viewer, invoice matching table, and manual override capabilities.

### Tasks
- [ ] Install PDF viewer:
  ```bash
  cd apps/web
  npm install react-pdf @react-pdf/renderer
  npm install --save-dev @types/react-pdf
  ```
- [ ] Create PDF viewer component in `apps/web/components/pdf-viewer.tsx`:
  ```typescript
  'use client';
  
  import { useState } from 'react';
  import { Document, Page, pdfjs } from 'react-pdf';
  import { ChevronLeft, ChevronRight, ZoomIn, ZoomOut } from 'lucide-react';
  import { Button } from '@/components/ui/button';
  import 'react-pdf/dist/esm/Page/AnnotationLayer.css';
  import 'react-pdf/dist/esm/Page/TextLayer.css';
  
  // Set worker URL
  pdfjs.GlobalWorkerOptions.workerSrc = `//unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.js`;
  
  interface PDFViewerProps {
    url: string;
  }
  
  export function PDFViewer({ url }: PDFViewerProps) {
    const [numPages, setNumPages] = useState<number | null>(null);
    const [pageNumber, setPageNumber] = useState(1);
    const [scale, setScale] = useState(1.0);
    
    function onDocumentLoadSuccess({ numPages }: { numPages: number }) {
      setNumPages(numPages);
    }
    
    const changePage = (offset: number) => {
      setPageNumber(prevPageNumber => prevPageNumber + offset);
    };
    
    const previousPage = () => changePage(-1);
    const nextPage = () => changePage(1);
    
    const zoomIn = () => setScale(s => Math.min(s + 0.2, 2.0));
    const zoomOut = () => setScale(s => Math.max(s - 0.2, 0.5));
    
    return (
      <div className="flex flex-col h-full">
        <div className="flex items-center justify-between p-2 border-b">
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="icon"
              onClick={previousPage}
              disabled={pageNumber <= 1}
            >
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <span className="text-sm">
              Page {pageNumber} of {numPages || '?'}
            </span>
            <Button
              variant="outline"
              size="icon"
              onClick={nextPage}
              disabled={pageNumber >= (numPages || 1)}
            >
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="icon" onClick={zoomOut}>
              <ZoomOut className="h-4 w-4" />
            </Button>
            <span className="text-sm">{Math.round(scale * 100)}%</span>
            <Button variant="outline" size="icon" onClick={zoomIn}>
              <ZoomIn className="h-4 w-4" />
            </Button>
          </div>
        </div>
        <div className="flex-1 overflow-auto p-4 bg-gray-100">
          <Document
            file={url}
            onLoadSuccess={onDocumentLoadSuccess}
            className="flex justify-center"
          >
            <Page
              pageNumber={pageNumber}
              scale={scale}
              className="shadow-lg"
            />
          </Document>
        </div>
      </div>
    );
  }
  ```
- [ ] Create remittance detail page in `apps/web/app/dashboard/remittances/[id]/page.tsx`:
  ```typescript
  'use client';
  
  import { useState, useEffect } from 'react';
  import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
  import { useParams, useRouter } from 'next/navigation';
  import { useSession } from '@/lib/hooks/use-session';
  import { Button } from '@/components/ui/button';
  import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
  import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
  } from '@/components/ui/table';
  import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
  } from '@/components/ui/select';
  import { Input } from '@/components/ui/input';
  import { PDFViewer } from '@/components/pdf-viewer';
  import { StatusBadge } from '@/components/status-badge';
  import { Remittance, RemittanceLine } from '@/lib/types/remittance';
  import { ArrowLeft, Save, Check, RotateCcw, Loader2 } from 'lucide-react';
  import { format } from 'date-fns';
  import { toast } from 'sonner';
  
  export default function RemittanceDetailPage() {
    const params = useParams();
    const router = useRouter();
    const queryClient = useQueryClient();
    const { organisation, user, canApproveRemittances } = useSession();
    const [pdfUrl, setPdfUrl] = useState<string | null>(null);
    const [editedLines, setEditedLines] = useState<Record<string, Partial<RemittanceLine>>>({});
    const [availableInvoices, setAvailableInvoices] = useState<any[]>([]);
    
    const remittanceId = params.id as string;
    
    // Fetch remittance details
    const { data: remittance, isLoading } = useQuery({
      queryKey: ['remittance', remittanceId],
      queryFn: async () => {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/remittances/${remittanceId}`,
          {
            headers: {
              'user-id': user.id || ''
            }
          }
        );
        
        if (!response.ok) throw new Error('Failed to fetch remittance');
        return response.json();
      },
      enabled: !!remittanceId && !!user.id
    });
    
    // Fetch PDF URL
    useEffect(() => {
      if (remittanceId && user.id) {
        fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/files/${remittanceId}/download`,
          {
            headers: {
              'user-id': user.id
            }
          }
        )
        .then(res => res.json())
        .then(data => setPdfUrl(data.url))
        .catch(err => console.error('Failed to fetch PDF:', err));
      }
    }, [remittanceId, user.id]);
    
    // Fetch available invoices
    useEffect(() => {
      if (organisation.id) {
        // Fetch from Xero via API
        // For now, mock data
        setAvailableInvoices([
          { id: 'inv-1', number: 'INV-001', total: 1000, outstanding: 1000 },
          { id: 'inv-2', number: 'INV-002', total: 2500, outstanding: 2500 },
          { id: 'inv-3', number: 'INV-003', total: 750, outstanding: 750 },
        ]);
      }
    }, [organisation.id]);
    
    // Save changes mutation
    const saveMutation = useMutation({
      mutationFn: async (data: { lines: any[], approve: boolean }) => {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/remittances/${remittanceId}/save-overrides`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'user-id': user.id || ''
            },
            body: JSON.stringify(data)
          }
        );
        
        if (!response.ok) throw new Error('Failed to save changes');
        return response.json();
      },
      onSuccess: (data, variables) => {
        toast.success(variables.approve ? 'Remittance approved' : 'Changes saved');
        queryClient.invalidateQueries({ queryKey: ['remittance', remittanceId] });
        setEditedLines({});
      },
      onError: () => {
        toast.error('Failed to save changes');
      }
    });
    
    // Retry extraction mutation
    const retryMutation = useMutation({
      mutationFn: async () => {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/remittances/${remittanceId}/retry`,
          {
            method: 'POST',
            headers: {
              'user-id': user.id || ''
            }
          }
        );
        
        if (!response.ok) throw new Error('Failed to retry extraction');
        return response.json();
      },
      onSuccess: () => {
        toast.success('Extraction retry started');
        queryClient.invalidateQueries({ queryKey: ['remittance', remittanceId] });
      },
      onError: () => {
        toast.error('Failed to retry extraction');
      }
    });
    
    const handleLineChange = (lineId: string, field: string, value: any) => {
      setEditedLines(prev => ({
        ...prev,
        [lineId]: {
          ...prev[lineId],
          [field]: value
        }
      }));
    };
    
    const handleSave = (approve: boolean = false) => {
      const lines = remittance.lines.map((line: RemittanceLine) => ({
        id: line.id,
        ...editedLines[line.id]
      }));
      
      saveMutation.mutate({ lines, approve });
    };
    
    const canEdit = remittance?.status === 'Error - Payments Unmatched' || 
                    remittance?.status === 'All payments matched - Awaiting Approval';
    
    const canRetry = remittance?.status === 'Error - Payments Unmatched';
    
    if (isLoading) {
      return (
        <div className="flex items-center justify-center h-96">
          <Loader2 className="h-8 w-8 animate-spin" />
        </div>
      );
    }
    
    if (!remittance) {
      return <div>Remittance not found</div>;
    }
    
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-4">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => router.back()}
          >
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <h1 className="text-2xl font-bold">Remittance Details</h1>
        </div>
        
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* PDF Viewer */}
          <Card className="h-[600px]">
            <CardHeader>
              <CardTitle>Document</CardTitle>
            </CardHeader>
            <CardContent className="h-[calc(100%-5rem)] p-0">
              {pdfUrl ? (
                <PDFViewer url={pdfUrl} />
              ) : (
                <div className="flex items-center justify-center h-full">
                  <Loader2 className="h-8 w-8 animate-spin" />
                </div>
              )}
            </CardContent>
          </Card>
          
          {/* Details and Lines */}
          <div className="space-y-6">
            {/* Remittance Info */}
            <Card>
              <CardHeader>
                <CardTitle>Payment Information</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-sm text-muted-foreground">Status</p>
                    <StatusBadge status={remittance.status} />
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Payment Date</p>
                    <p className="font-medium">
                      {remittance.payment_date
                        ? format(new Date(remittance.payment_date), 'dd/MM/yyyy')
                        : '-'}
                    </p>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Total Amount</p>
                    <p className="font-medium">
                      {remittance.total_amount
                        ? `$${remittance.total_amount.toFixed(2)}`
                        : '-'}
                    </p>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Reference</p>
                    <p className="font-medium">
                      {remittance.payment_reference || '-'}
                    </p>
                  </div>
                </div>
                {remittance.confidence_score !== null && (
                  <div>
                    <p className="text-sm text-muted-foreground">
                      AI Confidence: {Math.round(remittance.confidence_score * 100)}%
                    </p>
                  </div>
                )}
              </CardContent>
            </Card>
            
            {/* Invoice Lines */}
            <Card>
              <CardHeader>
                <div className="flex justify-between items-center">
                  <CardTitle>Invoice Mapping</CardTitle>
                  {canRetry && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => retryMutation.mutate()}
                      disabled={retryMutation.isPending}
                    >
                      <RotateCcw className="mr-2 h-4 w-4" />
                      Retry AI
                    </Button>
                  )}
                </div>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Invoice #</TableHead>
                      <TableHead>Amount</TableHead>
                      <TableHead>Match</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {remittance.lines?.map((line: RemittanceLine) => (
                      <TableRow key={line.id}>
                        <TableCell>{line.invoice_number}</TableCell>
                        <TableCell>
                          {canEdit ? (
                            <Input
                              type="number"
                              value={editedLines[line.id]?.manual_paid_amount ?? line.ai_paid_amount}
                              onChange={(e) => handleLineChange(
                                line.id,
                                'manual_paid_amount',
                                parseFloat(e.target.value)
                              )}
                              className="w-24"
                            />
                          ) : (
                            `$${(line.manual_paid_amount || line.ai_paid_amount).toFixed(2)}`
                          )}
                        </TableCell>
                        <TableCell>
                          {canEdit ? (
                            <Select
                              value={editedLines[line.id]?.override_invoice_id || line.ai_invoice_id || ''}
                              onValueChange={(value) => handleLineChange(
                                line.id,
                                'override_invoice_id',
                                value
                              )}
                            >
                              <SelectTrigger className="w-32">
                                <SelectValue placeholder="Select" />
                              </SelectTrigger>
                              <SelectContent>
                                {availableInvoices.map((inv) => (
                                  <SelectItem key={inv.id} value={inv.id}>
                                    {inv.number}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          ) : (
                            line.override_invoice_id || line.ai_invoice_id || '-'
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                
                {canEdit && canApproveRemittances && (
                  <div className="flex gap-2 mt-4 justify-end">
                    <Button
                      variant="outline"
                      onClick={() => handleSave(false)}
                      disabled={saveMutation.isPending}
                    >
                      <Save className="mr-2 h-4 w-4" />
                      Save Changes
                    </Button>
                    <Button
                      onClick={() => handleSave(true)}
                      disabled={saveMutation.isPending}
                    >
                      <Check className="mr-2 h-4 w-4" />
                      Save + Approve
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    );
  }
  ```
- [ ] Add detail endpoint in `apps/api/app/routers/remittances.py`:
  ```python
  @router.get("/{remittance_id}")
  async def get_remittance_detail(
      remittance_id: str,
      user_id: str = Header(...)
  ):
      """Get detailed remittance information"""
      db = get_db()
      
      # Get remittance with all related data
      result = db.table('remittances').select(
          '*, files(*), remittance_lines(*)'
      ).eq('id', remittance_id).execute()
      
      if not result.data:
          raise HTTPException(status_code=404, detail="Remittance not found")
      
      remittance = result.data[0]
      
      # Check access
      if not await check_organisation_access(user_id, remittance['organisation_id']):
          raise HTTPException(status_code=403, detail="Access denied")
      
      return remittance
  
  @router.post("/{remittance_id}/save-overrides")
  async def save_remittance_overrides(
      remittance_id: str,
      request: Dict[str, Any],
      user_id: str = Header(...)
  ):
      """Save manual overrides and optionally approve"""
      db = get_db()
      
      # Get remittance
      result = db.table('remittances').select('organisation_id, status').eq('id', remittance_id).execute()
      if not result.data:
          raise HTTPException(status_code=404, detail="Remittance not found")
      
      remittance = result.data[0]
      
      # Check access
      if not await check_organisation_access(user_id, remittance['organisation_id']):
          raise HTTPException(status_code=403, detail="Access denied")
      
      # Check status
      if remittance['status'] not in ['Error - Payments Unmatched', 'All payments matched - Awaiting Approval']:
          raise HTTPException(status_code=400, detail="Cannot edit in current status")
      
      try:
          # Update lines
          for line in request.get('lines', []):
              if 'manual_paid_amount' in line or 'override_invoice_id' in line:
                  update_data = {}
                  if 'manual_paid_amount' in line:
                      update_data['manual_paid_amount'] = line['manual_paid_amount']
                  if 'override_invoice_id' in line:
                      update_data['override_invoice_id'] = line['override_invoice_id']
                  
                  db.table('remittance_lines').update(update_data).eq('id', line['id']).execute()
          
          # If approving, update status
          if request.get('approve', False):
              db.table('remittances').update({
                  'status': 'Exported to Xero - Unreconciled'
              }).eq('id', remittance_id).execute()
              
              # TODO: Create payment in Xero
              
              await create_audit_log(
                  organisation_id=remittance['organisation_id'],
                  user_id=user_id,
                  action='remittance_approved',
                  remittance_id=remittance_id,
                  outcome='success'
              )
          else:
              await create_audit_log(
                  organisation_id=remittance['organisation_id'],
                  user_id=user_id,
                  action='overrides_saved',
                  remittance_id=remittance_id,
                  outcome='success'
              )
          
          return {"status": "success"}
          
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  ```
- [ ] Test remittance detail view
- [ ] Verify PDF viewer works
- [ ] Test manual override functionality
- [ ] Check save and approve flow

## Phase 4.5: Dashboard Updates

### Objective
Update the main dashboard to show RemitMatch-specific summary cards and quick actions.

### Tasks
- [ ] Create dashboard summary endpoint in `apps/api/app/routers/dashboard.py`:
  ```python
  from fastapi import APIRouter, HTTPException, Header
  from app.database import get_db
  from app.utils.database_helpers import check_organisation_access
  
  router = APIRouter()
  
  @router.get("/summary/{organisation_id}")
  async def get_dashboard_summary(
      organisation_id: str,
      user_id: str = Header(...)
  ):
      """Get dashboard summary for an organisation"""
      # Check access
      if not await check_organisation_access(user_id, organisation_id):
          raise HTTPException(status_code=403, detail="Access denied")
      
      try:
          db = get_db()
          
          # Get counts for different statuses
          result = db.table('remittances').select(
              'status',
              count='exact'
          ).eq('organisation_id', organisation_id).is_('deleted_at', 'null').execute()
          
          # Process counts
          status_counts = {}
          for item in result.data:
              status_counts[item['status']] = item.get('count', 0)
          
          return {
              'unmatched_remittances_count': status_counts.get('Error - Payments Unmatched', 0),
              'awaiting_approval_count': status_counts.get('All payments matched - Awaiting Approval', 0),
              'unreconciled_count': status_counts.get('Exported to Xero - Unreconciled', 0),
              'failed_ai_count': status_counts.get('Export Failed', 0),
              'total_remittances': sum(status_counts.values())
          }
          
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  ```
- [ ] Update main.py to include dashboard router:
  ```python
  from app.routers import stripe, test, organisations, users, xero, files, remittances, dashboard
  
  app.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])
  ```
- [ ] Update dashboard page in `apps/web/app/dashboard/page.tsx`:
  ```typescript
  'use client';
  
  import { useQuery } from '@tanstack/react-query';
  import { useSession } from '@/lib/hooks/use-session';
  import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
  import { Button } from '@/components/ui/button';
  import { 
    FileText, 
    AlertCircle, 
    Clock, 
    CheckCircle,
    Upload,
    ArrowUpRight
  } from 'lucide-react';
  import Link from 'next/link';
  import { useRouter } from 'next/navigation';
  
  export default function Dashboard() {
    const router = useRouter();
    const { organisation, user } = useSession();
    
    // Fetch dashboard summary
    const { data: summary } = useQuery({
      queryKey: ['dashboard-summary', organisation.id],
      queryFn: async () => {
        if (!organisation.id) return null;
        
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/dashboard/summary/${organisation.id}`,
          {
            headers: {
              'user-id': user.id || ''
            }
          }
        );
        
        if (!response.ok) throw new Error('Failed to fetch summary');
        return response.json();
      },
      enabled: !!organisation.id && !!user.id
    });
    
    const summaryCards = [
      {
        title: 'Awaiting Approval',
        value: summary?.awaiting_approval_count || 0,
        icon: Clock,
        color: 'text-blue-600',
        bgColor: 'bg-blue-100',
        link: '/dashboard/remittances?status=awaiting'
      },
      {
        title: 'Unmatched Payments',
        value: summary?.unmatched_remittances_count || 0,
        icon: AlertCircle,
        color: 'text-red-600',
        bgColor: 'bg-red-100',
        link: '/dashboard/remittances?status=unmatched'
      },
      {
        title: 'Unreconciled',
        value: summary?.unreconciled_count || 0,
        icon: FileText,
        color: 'text-yellow-600',
        bgColor: 'bg-yellow-100',
        link: '/dashboard/remittances?status=unreconciled'
      },
      {
        title: 'Total Remittances',
        value: summary?.total_remittances || 0,
        icon: CheckCircle,
        color: 'text-green-600',
        bgColor: 'bg-green-100',
        link: '/dashboard/remittances'
      }
    ];
    
    if (!organisation.id) {
      return (
        <div className="flex flex-col items-center justify-center h-96 text-center">
          <h2 className="text-2xl font-semibold mb-2">Welcome to RemitMatch</h2>
          <p className="text-muted-foreground mb-4">
            Please select an organisation to get started
          </p>
        </div>
      );
    }
    
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-bold">Dashboard</h1>
          <p className="text-muted-foreground">
            Overview of your remittance processing
          </p>
        </div>
        
        {/* Summary Cards */}
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {summaryCards.map((card) => {
            const Icon = card.icon;
            return (
              <Card 
                key={card.title}
                className="cursor-pointer hover:shadow-md transition-shadow"
                onClick={() => router.push(card.link)}
              >
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">
                    {card.title}
                  </CardTitle>
                  <div className={`${card.bgColor} p-2 rounded-lg`}>
                    <Icon className={`h-4 w-4 ${card.color}`} />
                  </div>
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">{card.value}</div>
                </CardContent>
              </Card>
            );
          })}
        </div>
        
        {/* Quick Actions */}
        <Card>
          <CardHeader>
            <CardTitle>Quick Actions</CardTitle>
          </CardHeader>
          <CardContent className="flex gap-2">
            <Button
              onClick={() => router.push('/dashboard/remittances?action=upload')}
            >
              <Upload className="mr-2 h-4 w-4" />
              Upload Remittance
            </Button>
            <Button
              variant="outline"
              onClick={() => router.push('/dashboard/remittances')}
            >
              View All Remittances
              <ArrowUpRight className="ml-2 h-4 w-4" />
            </Button>
          </CardContent>
        </Card>
        
        {/* Recent Activity */}
        <Card>
          <CardHeader>
            <CardTitle>Recent Activity</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-muted-foreground">
              Activity feed will be displayed here
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }
  ```
- [ ] Update sidebar to highlight Remittances link:
  ```typescript
  // In apps/web/app/dashboard/_components/dashboard-side-bar.tsx
  // Add after Projects link:
  <Link
    className={clsx("flex items-center gap-2 rounded-lg px-3 py-2 text-gray-500 transition-all hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-50", {
      "flex items-center gap-2 rounded-lg bg-gray-100 px-3 py-2 text-gray-900  transition-all hover:text-gray-900 dark:bg-gray-800 dark:text-gray-50 dark:hover:text-gray-50": pathname === "/dashboard/remittances"
    })}
    href="/dashboard/remittances"
  >
    <div className="border rounded-lg dark:bg-black dark:border-gray-800 border-gray-400 p-1 bg-white">
      <FileText className="h-3 w-3" />
    </div>
    Remittances
  </Link>
  ```
- [ ] Test dashboard summary cards
- [ ] Verify navigation from cards
- [ ] Check quick actions work

## Verification Checklist
- [ ] File upload creates remittance and stores file
- [ ] PDF extraction processes automatically after upload
- [ ] Remittances list shows all remittances with correct status
- [ ] Search and filtering work in list view
- [ ] Detail view displays PDF correctly
- [ ] Manual overrides can be saved
- [ ] Approval flow updates status correctly
- [ ] Retry extraction works for failed remittances
- [ ] Dashboard shows accurate counts
- [ ] All navigation flows work smoothly
- [ ] Error states are handled gracefully

## Next Steps
Once Phase 4 is complete, proceed to Phase 5: Integration & Polish, which will complete the API integration, implement subscription limits, and prepare for deployment.
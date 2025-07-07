import axios, { AxiosInstance, AxiosRequestConfig } from 'axios';
import { useAuth } from '@clerk/nextjs';

class ApiClient {
  private client: AxiosInstance;
  private baseURL: string;

  constructor() {
    this.baseURL = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8001';
    
    this.client = axios.create({
      baseURL: this.baseURL,
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor for auth token
    this.client.interceptors.request.use(
      (config) => {
        // Development logging
        if (process.env.NODE_ENV === 'development') {
          console.log(`🌐 API Request: ${config.method?.toUpperCase()} ${config.url}`);
        }
        return config;
      },
      (error) => {
        console.error('API Request Error:', error);
        return Promise.reject(error);
      }
    );

    // Response interceptor for error handling
    this.client.interceptors.response.use(
      (response) => {
        // Development logging
        if (process.env.NODE_ENV === 'development') {
          console.log(`✅ API Response: ${response.status} ${response.config.url}`);
        }
        return response;
      },
      (error) => {
        // Development logging
        if (process.env.NODE_ENV === 'development') {
          console.error(`❌ API Error: ${error.response?.status} ${error.config?.url}`, error.response?.data);
        }
        
        // Handle common errors
        if (error.response?.status === 401) {
          console.warn('API: Unauthorized request - token may be invalid');
        }
        
        return Promise.reject(error);
      }
    );
  }

  // Set auth token for requests
  setAuthToken(token: string) {
    this.client.defaults.headers.common['Authorization'] = `Bearer ${token}`;
  }

  // Remove auth token
  removeAuthToken() {
    delete this.client.defaults.headers.common['Authorization'];
  }

  // Health check endpoint
  async healthCheck() {
    try {
      const response = await this.client.get('/health');
      return response.data;
    } catch (error) {
      console.error('Health check failed:', error);
      throw error;
    }
  }

  // Generic request methods
  async get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.get<T>(url, config);
    return response.data;
  }

  async post<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.post<T>(url, data, config);
    return response.data;
  }

  async put<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.put<T>(url, data, config);
    return response.data;
  }

  async patch<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.patch<T>(url, data, config);
    return response.data;
  }

  async delete<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.delete<T>(url, config);
    return response.data;
  }

  // Get base URL
  getBaseURL(): string {
    return this.baseURL;
  }
}

// Create singleton instance
export const apiClient = new ApiClient();

// Hook for authenticated requests
export function useApiClient() {
  const { getToken } = useAuth();

  const authenticatedClient = {
    ...apiClient,
    
    // Override methods to include auth token
    async get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
      const token = await getToken();
      if (token) {
        apiClient.setAuthToken(token);
      }
      return apiClient.get<T>(url, config);
    },

    async post<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
      const token = await getToken();
      if (token) {
        apiClient.setAuthToken(token);
      }
      return apiClient.post<T>(url, data, config);
    },

    async put<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
      const token = await getToken();
      if (token) {
        apiClient.setAuthToken(token);
      }
      return apiClient.put<T>(url, data, config);
    },

    async patch<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
      const token = await getToken();
      if (token) {
        apiClient.setAuthToken(token);
      }
      return apiClient.patch<T>(url, data, config);
    },

    async delete<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
      const token = await getToken();
      if (token) {
        apiClient.setAuthToken(token);
      }
      return apiClient.delete<T>(url, config);
    },
  };

  return authenticatedClient;
}
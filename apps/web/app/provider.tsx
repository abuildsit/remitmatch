"use client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import { ReactNode, useState } from "react";
import { toast } from "sonner";

export default function Provider({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient({
    defaultOptions: {
      queries: {
        retry: (failureCount, error: any) => {
          // Don't retry on 4xx errors (client errors)
          if (error?.response?.status >= 400 && error?.response?.status < 500) {
            return false;
          }
          // Retry up to 3 times for other errors
          return failureCount < 3;
        },
        retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
        staleTime: 5 * 60 * 1000, // 5 minutes
        gcTime: 10 * 60 * 1000, // 10 minutes (was cacheTime)
      },
      mutations: {
        onError: (error: any) => {
          // Development logging
          if (process.env.NODE_ENV === 'development') {
            console.error('Mutation Error:', error);
          }
          
          // Show user-friendly error messages
          const message = error?.response?.data?.message || 
                         error?.message || 
                         'An unexpected error occurred';
          
          toast.error(message);
        },
        retry: (failureCount, error: any) => {
          // Don't retry mutations on client errors
          if (error?.response?.status >= 400 && error?.response?.status < 500) {
            return false;
          }
          // Retry once for server errors
          return failureCount < 1;
        },
      },
    },
  }));

  return (
    <QueryClientProvider client={queryClient}>
      <ReactQueryDevtools 
        initialIsOpen={false} 
        position="bottom-right"
        buttonPosition="bottom-right"
      />
      {children}
    </QueryClientProvider>
  );
}

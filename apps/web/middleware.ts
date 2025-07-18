import { NextResponse } from "next/server";
import config from "./config";

let clerkMiddleware: (arg0: (auth: any, req: any) => any) => { (arg0: any): any; new(): any; }, createRouteMatcher;

if (config.auth.enabled) {
  try {
    ({ clerkMiddleware, createRouteMatcher } = require("@clerk/nextjs/server"));
  } catch (error) {
    console.warn("Clerk modules not available. Auth will be disabled.");
    config.auth.enabled = false;
  }
}

const isProtectedRoute = config.auth.enabled
  ? createRouteMatcher(["/dashboard(.*)"])
  : () => false;

export default function middleware(req: any) {
  if (config.auth.enabled) {
    return clerkMiddleware(async (auth, req) => {
      const resolvedAuth = await auth();

      // In development mode, log auth status for debugging
      if (process.env.NODE_ENV === "development" && process.env.DEV_MODE === "true") {
        console.log(`🔐 Auth check for ${req.nextUrl.pathname}:`, {
          userId: resolvedAuth.userId,
          isProtected: isProtectedRoute(req),
        });
      }

      if (!resolvedAuth.userId && isProtectedRoute(req)) {
        return resolvedAuth.redirectToSignIn();
      } else {
        return NextResponse.next();
      }
    })(req);
  } else {
    return NextResponse.next();
  }
}

export const middlewareConfig = {
  matcher: [
    "/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest)).*)",
    "/(api|trpc)(.*)",
  ],
};
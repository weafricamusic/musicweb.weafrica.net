"use client";

import { useEffect } from "react";

declare global {
    interface Window {
        $zoho?: {
            salesiq?: {
                ready: (callback: () => void) => void;
                floatbutton?: {
                    hide: () => void;
                    show: () => void;
                };
                visitor?: {
                    name: (name: string) => void;
                    email: (email: string) => void;
                    contact: (contactId: string) => void;
                };
            };
        };
    }
}

export default function ZohoSalesIQ() {
    useEffect(() => {
        // Initialize Zoho SalesIQ
        window.$zoho = window.$zoho || {};
        window.$zoho.salesiq = window.$zoho.salesiq || { ready: function () { } };

        // Load the SalesIQ script if not already loaded
        if (!document.getElementById("zsiqscript")) {
            const script = document.createElement("script");
            script.id = "zsiqscript";
            script.src =
                "https://salesiq.zohopublic.com/widget?wc=siq25e9a3e58012b687f7dda2ab0b5b7a196b36e836020c53972df3bc0d09853e55";
            script.defer = true;
            document.head.appendChild(script);
        }

        // Optional: Set visitor information when ready
        window.$zoho.salesiq.ready = function () {
            console.log("Zoho SalesIQ is ready");
            // You can customize visitor info here if needed
            // window.$zoho.salesiq.visitor.name("User Name");
            // window.$zoho.salesiq.visitor.email("user@example.com");
        };

        return () => {
            // Cleanup if needed (optional)
        };
    }, []);

    return null; // This component doesn't render anything visible
}
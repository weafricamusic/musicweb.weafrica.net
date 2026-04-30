# Zoho SalesIQ Integration Guide

## Overview
Zoho SalesIQ has been successfully integrated into your WeAfrica Music platform for live chat and visitor tracking.

## Integration Points

### 1. Flutter Web App (`web/index.html`)
The SalesIQ widget is embedded directly in the HTML head section. It will appear on all pages of your main music platform.

**Location:** `web/index.html` (lines 40-43)

### 2. Next.js Admin Dashboard (`admin_dashboard/`)
A reusable React component handles the SalesIQ integration for the admin dashboard.

**Component:** `admin_dashboard/src/components/ZohoSalesIQ.tsx`
**Usage:** Integrated into `admin_dashboard/src/app/layout.tsx`

## Features Enabled

✅ **Live Chat Widget** - Visitors can initiate conversations with your support team
✅ **Visitor Tracking** - Monitor visitor behavior and engagement
✅ **Visitor Information** - Ability to set visitor details (name, email, contact ID)
✅ **Real-time Notifications** - Get instant alerts when visitors need assistance

## Managing the Chat Widget

### In Zoho SalesIQ Dashboard
1. Log in to your Zoho SalesIQ account
2. Go to **Settings > Websites**
3. You can customize:
   - Widget appearance (colors, position)
   - Chat availability hours
   - Automated greetings
   - Offline messages

### Hiding/Showing the Widget Programmatically
If you need to hide the chat widget on certain pages (e.g., during checkout), you can use:

```javascript
// Hide the widget
window.$zoho.salesiq.floatbutton.hide();

// Show the widget
window.$zoho.salesiq.floatbutton.show();
```

### Setting Visitor Information
You can identify visitors by setting their information:

```javascript
window.$zoho.salesiq.ready(function() {
  window.$zoho.salesiq.visitor.name("John Doe");
  window.$zoho.salesiq.visitor.email("john@example.com");
  // Add more visitor details as needed
});
```

## Testing the Integration

### 1. Test on Flutter Web
```bash
# Navigate to your project root
cd /Users/weafrica/weafrica_music1

# Build and run the web app
flutter build web
# Or run in debug mode
flutter run -d chrome
```

Visit your web app and look for the chat widget in the bottom-right corner.

### 2. Test on Next.js Admin Dashboard
```bash
# Navigate to admin dashboard
cd admin_dashboard

# Install dependencies (if needed)
npm install

# Run development server
npm run dev
```

Open `http://localhost:3000` and check for the chat widget.

## Troubleshooting

### Widget Not Appearing
1. **Check Browser Console** - Look for any JavaScript errors
2. **Verify Script Loading** - Ensure the SalesIQ script is loading (check Network tab)
3. **Clear Browser Cache** - Sometimes cached files can cause issues
4. **Check Zoho Account** - Ensure your SalesIQ account is active and properly configured

### Widget Appears but Not Functional
1. **Check Zoho Dashboard** - Verify your widget is published
2. **Check Availability Hours** - Ensure you're testing during configured hours
3. **Test in Incognito Mode** - Browser extensions might interfere

### Build Issues (Next.js)
If you encounter TypeScript errors:
```bash
# Clear Next.js cache
rm -rf .next

# Rebuild
npm run build
```

## Advanced Customization

### Custom Visitor Tracking
You can track custom visitor data by extending the ZohoSalesIQ component:

```typescript
// In admin_dashboard/src/components/ZohoSalesIQ.tsx
window.$zoho.salesiq.ready = function() {
  // Add custom tracking
  window.$zoho.salesiq.visitor.name("Admin User");
  window.$zoho.salesiq.visitor.email("admin@weafrica.music");
  
  // Track custom events
  console.log("Admin dashboard loaded - SalesIQ active");
};
```

### Integration with User Authentication
When users log in, you can pass their information to SalesIQ:

```typescript
// After user authentication
if (user && window.$zoho?.salesiq) {
  window.$zoho.salesiq.visitor.name(user.name);
  window.$zoho.salesiq.visitor.email(user.email);
}
```

## Support and Resources

- **Zoho SalesIQ Documentation:** https://www.zoho.com/salesiq/help/
- **Zoho Support:** Contact Zoho support for account-specific issues
- **Widget Customization:** Use Zoho's dashboard for most customizations

## Security Considerations

✅ The widget code uses HTTPS for secure communication
✅ No sensitive data is exposed in the client-side code
✅ Visitor data is handled by Zoho's secure infrastructure

## Next Steps

1. **Test thoroughly** on both platforms
2. **Customize the widget** appearance in your Zoho dashboard
3. **Set up automated greetings** and offline messages
4. **Configure availability hours** for your support team
5. **Train your team** on using the Zoho SalesIQ operator console

## Maintenance

- Regularly check your Zoho SalesIQ dashboard for visitor analytics
- Update the widget code if Zoho releases new versions
- Monitor chat performance and visitor engagement metrics

---

**Integration completed:** April 23, 2026
**Integrated by:** Claude Code (AI Assistant)
**Platforms:** Flutter Web + Next.js Admin Dashboard
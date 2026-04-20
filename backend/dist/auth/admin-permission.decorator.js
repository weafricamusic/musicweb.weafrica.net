"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ADMIN_PERMISSIONS_KEY = void 0;
exports.RequireAdminPermission = RequireAdminPermission;
const common_1 = require("@nestjs/common");
exports.ADMIN_PERMISSIONS_KEY = 'admin_permissions_required';
function RequireAdminPermission(...permissions) {
    return (0, common_1.SetMetadata)(exports.ADMIN_PERMISSIONS_KEY, permissions);
}
//# sourceMappingURL=admin-permission.decorator.js.map
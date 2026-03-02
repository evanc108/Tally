package middleware

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

const (
	MemberIDKey  = "member_id"
	IsLeaderKey  = "is_leader"
)

// RequireGroupMember verifies the authenticated Clerk user is a member of the
// group identified by the ":id" URL parameter. On success it stores the
// member's UUID and leader flag in the gin context so downstream handlers
// don't need to re-query.
func RequireGroupMember(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		clerkUserID, ok := c.Get(ClerkUserIDKey)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}

		groupID := c.Param("id")
		if _, err := uuid.Parse(groupID); err != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "invalid group id"})
			return
		}

		var memberID uuid.UUID
		var isLeader bool
		err := db.QueryRowContext(c.Request.Context(),
			`SELECT id, is_leader FROM members WHERE group_id = $1 AND user_id = $2`,
			groupID, clerkUserID,
		).Scan(&memberID, &isLeader)
		if err == sql.ErrNoRows {
			c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
			return
		}

		c.Set(MemberIDKey, memberID)
		c.Set(IsLeaderKey, isLeader)
		c.Next()
	}
}

// RequireGroupLeader is like RequireGroupMember but additionally requires the
// member to have is_leader = true. Returns 403 if the user is a member but
// not a leader.
func RequireGroupLeader(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		clerkUserID, ok := c.Get(ClerkUserIDKey)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}

		groupID := c.Param("id")
		if _, err := uuid.Parse(groupID); err != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "invalid group id"})
			return
		}

		var memberID uuid.UUID
		var isLeader bool
		err := db.QueryRowContext(c.Request.Context(),
			`SELECT id, is_leader FROM members WHERE group_id = $1 AND user_id = $2`,
			groupID, clerkUserID,
		).Scan(&memberID, &isLeader)
		if err == sql.ErrNoRows {
			c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
			return
		}
		if !isLeader {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "leader access required"})
			return
		}

		c.Set(MemberIDKey, memberID)
		c.Set(IsLeaderKey, isLeader)
		c.Next()
	}
}

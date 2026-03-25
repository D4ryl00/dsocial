package social

import (
	"strings"

	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

var (
	gUserPostsByAddress avl.Tree // user's address -> *UserPosts
	gUserAddressByName  avl.Tree // user's username -> address
	postsCtr            uint64   // increments Post.id globally

	// gRealmPath is the realm's relative URL path (e.g. "/r/g1.../social"),
	// derived from the deployed package path at init time.
	gRealmPath string
)

func init() {
	pkgPath := runtime.CurrentRealm().PkgPath()
	// Strip the chain domain (everything before the first "/") to get the
	// relative path suitable for markdown links: "/r/g1.../social".
	if idx := strings.Index(pkgPath, "/"); idx >= 0 {
		gRealmPath = pkgPath[idx:]
	}
}

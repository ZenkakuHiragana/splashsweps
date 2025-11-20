
---@class ss
local ss = SplashSWEPs

---Indicates the color of the Red-Black tree. Red is true.
---@alias ss.RBTreeColor boolean
local RED = true
local BLACK = false

---@generic T
---@param a T
---@param b T
---@return boolean
local function defaultLessFunc(a, b) return a < b end

---@class ss.RBTreeNode
---@field data any
---@field left ss.RBTreeNode?
---@field right ss.RBTreeNode?
---@field parent ss.RBTreeNode?
---@field color ss.RBTreeColor

---@param node ss.RBTreeNode?
---@return boolean
local function isRed(node)
    if not node then return false end
    return node.color -- == RED == true
end

---Rotates a node to the left.
---@param tree ss.RBTree
---@param node ss.RBTreeNode
local function rotateLeft(tree, node)
    local rightChild = node.right
    if not rightChild then return end

    node.right = rightChild.left
    if rightChild.left then
        rightChild.left.parent = node
    end

    rightChild.parent = node.parent
    if not node.parent then
        tree.root = rightChild
    elseif node == node.parent.left then
        node.parent.left = rightChild
    else
        node.parent.right = rightChild
    end

    rightChild.left = node
    node.parent = rightChild
end

---Rotates a node to the right.
---@param tree ss.RBTree
---@param node ss.RBTreeNode
local function rotateRight(tree, node)
    local leftChild = node.left
    if not leftChild then return end

    node.left = leftChild.right
    if leftChild.right then
        leftChild.right.parent = node
    end

    leftChild.parent = node.parent
    if not node.parent then
        tree.root = leftChild
    elseif node == node.parent.right then
        node.parent.right = leftChild
    else
        node.parent.left = leftChild
    end

    leftChild.right = node
    node.parent = leftChild
end

---Rebalances the tree after an insertion.
---@param tree ss.RBTree
---@param node ss.RBTreeNode
local function insertRebalance(tree, node)
    local currentNode = node
    while currentNode and currentNode.parent and isRed(currentNode.parent) do
        local parent = currentNode.parent ---@type ss.RBTreeNode
        local grandParent = parent.parent

        if not grandParent then
            break
        end
        if parent == grandParent.left then
            local uncle = grandParent.right
            if isRed(uncle) then
                parent.color = BLACK
                uncle.color = BLACK
                grandParent.color = RED
                currentNode = grandParent
            else
                if currentNode == parent.right then
                    currentNode = parent
                    rotateLeft(tree, currentNode)
                    parent = currentNode.parent ---@type ss.RBTreeNode
                    grandParent = parent.parent
                end

                if parent then
                    parent.color = BLACK
                end
                if grandParent then
                    grandParent.color = RED
                    rotateRight(tree, grandParent)
                end
            end
        else
            local uncle = grandParent.left
            if isRed(uncle) then
                parent.color = BLACK
                uncle.color = BLACK
                grandParent.color = RED
                currentNode = grandParent
            else
                if currentNode == parent.left then
                    currentNode = parent
                    rotateRight(tree, currentNode)
                    parent = currentNode.parent ---@type ss.RBTreeNode
                    grandParent = parent.parent
                end

                if parent then
                    parent.color = BLACK
                end
                if grandParent then
                    grandParent.color = RED
                    rotateLeft(tree, grandParent)
                end
            end
        end
    end

    if tree.root then
        tree.root.color = BLACK
    end
end

---Creates a new CUtlRBTree-like instance.
---@generic T
---@param lessFunc (fun(a: T, b: T): boolean)?
---@return ss.RBTree
function ss.CreateRBTree(lessFunc)
    ---@class ss.RBTree
    ---@field root ss.RBTreeNode?
    local tree = {
        root = nil,
        lessFunc = lessFunc or defaultLessFunc,
        count = 0,
    }

    ---Inserts a new element into the tree.
    ---@param data ss.SortableLightmapInfo.Surface
    function tree:Insert(data)
        local parent = nil
        local current = self.root
        local isLeftChild = false

        while current do
            parent = current
            if self.lessFunc(data, current.data) then
                current = current.left
                isLeftChild = true
            else
                current = current.right
                isLeftChild = false
            end
        end

        ---@type ss.RBTreeNode
        local newNode = {
            data = data,
            left = nil,
            right = nil,
            parent = parent,
            color = RED
        }

        if not parent then
            self.root = newNode
        elseif isLeftChild then
            parent.left = newNode
        else
            parent.right = newNode
        end

        self.count = self.count + 1
        insertRebalance(self, newNode)
    end

    ---Returns an iterator for inorder traversal.
    ---@return fun(): ss.SortableLightmapInfo.Surface?
    function tree:Pairs()
        local function firstInorder(node)
            if not node then return nil end
            local current = node
            while current.left do
                current = current.left ---@type ss.RBTreeNode
            end
            return current
        end

        local function nextInorder(node)
            if not node then return nil end

            if node.right then
                return firstInorder(node.right)
            end

            local current = node
            local parent = current.parent ---@type ss.RBTreeNode
            while parent and current == parent.right do
                current, parent = parent, parent.parent
            end
            return parent
        end

        local currentNode = firstInorder(self.root)

        return function()
            if not currentNode then
                return nil
            end

            local data = currentNode.data
            currentNode = nextInorder(currentNode)
            return data
        end
    end

    return tree
end


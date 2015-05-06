#include <stdlib.h>

typedef struct Node_t { int val; struct Node_t* next; } Node;

int sumList(Node* l)
{
    Node* nd;
    int sum;
    int i;
    for (i = 0; i < 500000000; ++i)
    {
        sum = 0;
        for (nd = l; nd != 0; nd = nd->next)
            sum += nd->val;
    }

    return sum;
}

int main()
{
    Node* list = 0;
    int i;
    for (i = 0; i < 10; ++i)
    {
        Node* newNode = malloc(sizeof(Node));
        newNode->val = i;
        newNode->next = list;
        list = newNode;
    }

    sumList(list);
    return 0;
}


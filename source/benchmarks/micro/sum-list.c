#include <stdlib.h>

typedef struct Node_t { int val; struct Node_t* next; } Node;

Node* list = 0;

double sumList(Node* l)
{
    Node* node;
    double sum;
    int i;
    for (i = 0; i < 500000000; ++i)
    {
        sum = 0;
        for (node = l; node != 0; node = node->next)
            sum += node->val;
    }

    return sum;
}

void main()
{
    int i;
    for (i = 0; i < 10; ++i)
    {
        Node* newNode = malloc(sizeof(Node));
        newNode->val = i;
        newNode->next = list;
        list = newNode;
    }

    sumList(list);
}

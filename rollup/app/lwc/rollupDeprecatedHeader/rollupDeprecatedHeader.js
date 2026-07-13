import { LightningElement, wire } from 'lwc';
import { gql, graphql } from 'lightning/graphql';

export default class RollupDeprecatedHeader extends LightningElement {
  fallback = '/lightning/setup/CustomMetadata/home';
  linkToCMDTSetupPage = '/lightning/setup/CustomMetadata/page?address=%2F{0}%3Fsetupid%3DCustomMetadata';

  get query() {
    return `
      query {
        uiapi {
          query {
            EntityDefinition (
              first: 1
              where: { DeveloperName: { eq: "Rollup" }}
            ) {
              edges {
                node {
                  DurableId {
                    value
                  }
                }
              }
            }
          }
        }
      }
    `;
  }

  get resolvedQuery() {
    return gql(this.query);
  }

  @wire(graphql, { query: '$resolvedQuery' })
  gqlQuery({ data, errors }) {
    if (data) {
      if (data.uiapi.query.EntityDefinition.edges.length > 0) {
        this.linkToCMDTSetupPage = this.linkToCMDTSetupPage.replace('{0}', data.uiapi.query.EntityDefinition.edges[0].node.DurableId.value);
      } else {
        this.linkToCMDTSetupPage = this.fallback;
      }
    } else if (errors) {
      this.linkToCMDTSetupPage = this.fallback;
    }
  }
}

import React from 'react'
import {connect} from 'react-redux'
import {bindActionCreators} from 'redux'

import {Grid, Button} from '@material-ui/core'
import Dialog from '@material-ui/core/Dialog';
import DialogActions from '@material-ui/core/DialogActions';
import DialogContent from '@material-ui/core/DialogContent';
import DialogContentText from '@material-ui/core/DialogContentText';
import DialogTitle from '@material-ui/core/DialogTitle';
import TextField from '@material-ui/core/TextField';
import Slide from '@material-ui/core/Slide';

import {web3} from '../../utils/getWeb3'
import {addAddress} from "../../modules/sets/actions";
import SetOverview from "../../components/SetOverview";
import EmptyState from "../../components/EmptyState";
import './HomePage.scss'

function Transition(props) {
  return <Slide direction="up" {...props} />;
}

class HomePage extends React.Component {
  state = {
    open: false,
    address: '',
    invalidAddress: null
  }

  componentWillReceiveProps(nextProps) {
    let {sets} = this.props
    if (sets.loading && !nextProps.sets.loading && this.state.open) {
      if(nextProps.sets.data[this.state.address]){
        this.setState({open: false, address: ''})
      }
    }
    if (nextProps.sets.failedAddresses){
      if (sets.failedAddresses.length !== nextProps.sets.failedAddresses.length){
        if (nextProps.sets.failedAddresses.indexOf(this.state.address) > -1) {
          this.setState({invalidAddress: 'Address does not belong to TCR standard', address: ''})
        }
      }
    }
  }

  openModal = () => {
    if (!this.state.open) {
      this.setState({open: true})
    }
  }

  handleClose = () => {
    if (this.state.open) {
      this.setState({
        open: false,
        invalidAddress: null,
        address: ''
      })
    }
  }

  handleInput = (ev) => {
    ev.preventDefault()
    let address = ev.target.value
    if (address.length > 42) {
      address = address.substring(0, 42)
    }
    this.setState({address})
  }

  submitAddress = () => {
    let {address} = this.state
    let {sets} = this.props

    if (!sets.loading) {
      if (web3.utils.isAddress(address)) {
        if (sets.failedAddresses.indexOf(address) > -1){
          this.setState({invalidAddress: 'Address does not belong to TCR standard', address: ''})
        } else {
          if (sets.data[this.state.address]) {
            this.setState({invalidAddress: 'Address already in dashboard', address: ''})
          } else {
            this.setState({invalidAddress: null})
            this.props.addAddress(address)
          }
        }
      } else {
        this.setState({invalidAddress: 'Please input a valid address'})
      }
    }
  }

  navigate = () => {
    this.props.history.push('/create-set')
  }

  render() {
    let {sets} = this.props;
    if (!sets) {
      return <div>Loading...</div>
    }

    let setsMap = Object.keys(sets.data).map(key => sets.data[key])

    return (
      <div className={'home-page container'}>
        <Grid container>
          <Grid item xs={6}>
            <h1>Participate</h1>
          </Grid>
          <Grid item xs={6} className={'create-set'}>
            <div className={'add-button'}>
              <Button onClick={this.openModal}>Add set</Button>
            </div>
            <div className={'create-link'}>
              <Button onClick={this.navigate}>Create set</Button>
            </div>
          </Grid>
        </Grid>
        <Grid container className={'table-page'}>
          <Grid item xs={6}>
            <div className={'th'}>Name of the set</div>
          </Grid>
          <Grid item xs={2}>
            <div className={'th'}>Set address</div>
          </Grid>
          <Grid item xs={2}>
            <div className={'th'}>Token</div>
          </Grid>
          <Grid item xs={2}>
            <div className={'th'}>Your tokens</div>
          </Grid>
        </Grid>
        {setsMap.map(set => {
          return <SetOverview key={set.address} set={set}/>
        })}

        {(!setsMap || setsMap.length === 0) && (
          <EmptyState>
            No sets to show.<br/>
            Please add with the button at the top right corner.
          </EmptyState>
        )}

        <Dialog
          open={this.state.open}
          TransitionComponent={Transition}
          keepMounted
          onClose={this.handleClose}
          aria-labelledby="alert-dialog-slide-title"
          aria-describedby="alert-dialog-slide-description"
          disableBackdropClick
        >
          <DialogTitle id="alert-dialog-slide-title">
            {"Add your TCR"}
          </DialogTitle>
          <DialogContent>
            <DialogContentText id="alert-dialog-slide-description">
              Paste below the address of the TCR that you want to add to the dashboard
            </DialogContentText>
            <TextField
              autoFocus
              margin="dense"
              id="address"
              label="TCR Address"
              type="email"
              placeholder="0x000.."
              fullWidth
              error={!(!this.state.invalidAddress)}
              onChange={this.handleInput}
              value={this.state.address}
            />
            {this.state.invalidAddress && (
              <span className={'input-error'}>
                {this.state.invalidAddress}
              </span>
            )}
          </DialogContent>
          <DialogActions>
            <Button
              disabled={sets.loading}
              onClick={this.handleClose}
              color="primary"
            >
              Cancel
            </Button>
            <Button
              disabled={sets.loading}
              onClick={this.submitAddress}
              color="primary"
            >
              Add
            </Button>
          </DialogActions>
        </Dialog>
      </div>
    )
  }
}

const mapStateToProps = (state) => {
  return {
    sets: state.sets
  }
}

const mapDispatchToProps = (dispatch) => {
  return bindActionCreators({addAddress}, dispatch);
};

export default connect(mapStateToProps, mapDispatchToProps)(HomePage)